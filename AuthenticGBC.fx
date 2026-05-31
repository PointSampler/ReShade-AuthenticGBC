/*
    Authentic GBC - ReShade port
    --------------------------------------------------------------------------
    Original "Authentic GBC" v2.2 by fishku, public domain (CC0).
    Renders Game Boy Color subpixels (with the characteristic notch) using
    analytical rectangle coverage for clean anti-aliasing.

    This file is a self-contained ReShade FX (.fx) port of the libretro slang
    shader. The original two passes (linearize -> rasterize) are folded into a
    single pass: the linearization is applied inline to the four sampled texels,
    which produces output identical to the two-pass preset but without an
    intermediate full-screen buffer. The slang includes coverage.inc, shared.inc
    and parameters.inc are inlined below.

    IMPORTANT - resolution model:
    ReShade runs on the full backbuffer and has no concept of the emulator's
    native framebuffer (the slang shader's "OriginalSize" / 160x144). The grid
    is instead defined by the "Emulated resolution" control below, and the
    shader assumes that emulated image fills the ReShade backbuffer. For the
    LCD grid to line up with real console pixels, run the content so it fills
    the screen (ideally nearest-neighbour scaled). Letterbox bars will not be
    masked.
*/

#include "ReShade.fxh"

// ---------------------------------------------------------------------------
// Parameters (from parameters.inc + the ReShade-specific resolution control)
// ---------------------------------------------------------------------------

uniform float2 AUTH_GBC_RES <
    ui_type = "drag";
    ui_label = "Source resolution (px)";
    ui_tooltip = "Native pixel resolution of the source content; the LCD grid is built from this.\n"
                 "Examples: Game Boy / GBC 160x144, GBA 240x160, NES 256x240, SNES 256x224,\n"
                 "Genesis 320x224. Set it to match whatever you're applying the shader to.";
    ui_min = 1.0; ui_max = 2048.0; ui_step = 1.0;
    ui_category = "Authentic GBC";
> = float2(160.0, 144.0);

uniform float AUTH_GBC_BRIG <
    ui_type = "slider";
    ui_label = "Add brightness";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
    ui_category = "Authentic GBC";
> = 0.6;

uniform float AUTH_GBC_BLUR <
    ui_type = "slider";
    ui_label = "Anti-banding smoothing";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
    ui_category = "Authentic GBC";
> = 0.3;

uniform bool AUTH_GBC_SUBPX <
    ui_label = "Enable subpixel rendering";
    ui_category = "Authentic GBC";
> = false;

uniform int AUTH_GBC_SUBPX_ORIENTATION <
    ui_type = "combo";
    ui_label = "Subpixel layout";
    ui_items = "RGB\0RGB vertical\0BGR\0BGR vertical\0";
    ui_category = "Authentic GBC";
> = 0;

uniform int AUTH_GBC_MODE <
    ui_type = "combo";
    ui_label = "Quality";
    ui_tooltip = "Accurate: Gaussian-smoothed rectangles (matches the default slang preset).\n"
                 "Fast: box-filter approximation with gamma 2.0 (cheaper).";
    ui_items = "Accurate (Gaussian)\0Fast (box filter)\0";
    ui_category = "Authentic GBC";
> = 0;

uniform int AUTH_GBC_FIT <
    ui_type = "combo";
    ui_label = "Content scaling";
    ui_tooltip = "Fill screen: the console image is assumed to cover the whole screen (use for\n"
                 "fullscreen / widescreen games). Centered: an aspect-correct image sits in the\n"
                 "middle with untouched borders (use when emulating GBC pillarboxed on a wider screen).";
    ui_items = "Fill screen\0Centered (pillarbox)\0";
    ui_category = "Authentic GBC";
> = 0;

uniform bool AUTH_GBC_FIT_INTEGER <
    ui_label = "Snap to integer scale";
    ui_tooltip = "Centered mode only. Match an emulator using integer scaling so the grid lands\n"
                 "exactly on console pixels. Turn off if your emulator scales to fit exactly.";
    ui_category = "Authentic GBC";
> = true;

uniform float2 AUTH_GBC_OFFSET <
    ui_type = "drag";
    ui_label = "Center nudge (px)";
    ui_tooltip = "Centered mode only. Fine offset of the content rectangle if it isn't perfectly centered.";
    ui_min = -512.0; ui_max = 512.0; ui_step = 1.0;
    ui_category = "Authentic GBC";
> = float2(0.0, 0.0);

uniform int AUTH_GBC_ASPECT <
    ui_type = "combo";
    ui_label = "Display aspect";
    ui_tooltip = "Centered mode only. Shape of the content rectangle.\n"
                 "Square pixels: 1:1 pixels (correct for Game Boy / GBC).\n"
                 "4:3 (CRT): classic TV aspect for NES / SNES / Genesis, etc.\n"
                 "Custom: set your own width / height ratio below.";
    ui_items = "Square pixels\0" "4:3 (CRT)\0" "Custom\0";
    ui_category = "Authentic GBC";
> = 0;

uniform float AUTH_GBC_ASPECT_CUSTOM <
    ui_type = "drag";
    ui_label = "Custom aspect (w / h)";
    ui_tooltip = "Centered mode only. Used when Display aspect is set to Custom (e.g. 1.333 = 4:3).";
    ui_min = 0.1; ui_max = 4.0; ui_step = 0.01;
    ui_category = "Authentic GBC";
> = 1.3333;

// Note: the slang shader's "Rotation" built-in only remaps the subpixel
// orientation, and is assumed 0 (no rotation) here. It is baked into the
// subpixel direction selection below.

// ---------------------------------------------------------------------------
// Source sampler: point filtering + clamp, matching filter_linear = false.
// ---------------------------------------------------------------------------

sampler2D AuthGBCSource {
    Texture   = ReShade::BackBufferTex;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    AddressW  = CLAMP;
};

// ---------------------------------------------------------------------------
// coverage.inc  (misc/shaders/coverage/coverage.inc)
// Analytical intersection area between a pixel square and a rectangle.
// ---------------------------------------------------------------------------

float intersect_rect_area(float4 px_square, float4 rect) {
    const float2 bl = max(px_square.xy, rect.xy);
    const float2 tr = min(px_square.zw, rect.zw);
    const float2 coverage = max(tr - bl, float2(0.0, 0.0));
    return coverage.x * coverage.y;
}

float intersect_blurred_rect_area(float4 px_square, float4 rect, float blur) {
    const float2 range2 = rect.zw - rect.xy;
    const float4 range = range2.xyxy;
    const float4 lin = clamp(px_square - rect.xyxy, float4(0.0, 0.0, 0.0, 0.0), range);

    // Early out: if blur is negligible, return the sharp rectangle area.
    if (blur < 1.0e-6) {
        return (lin.z - lin.x) * (lin.w - lin.y);
    }

    const float2 center2 = 0.5 * (rect.xy + rect.zw);
    const float4 center = center2.xyxy;
    const float4 dist_to_center = abs(px_square - center);
    const float4 blur_vec = float4(blur, blur, blur, blur);

    const float4 x_n =
        max(0.5 * (max(range, blur_vec) + blur_vec) - dist_to_center, float4(0.0, 0.0, 0.0, 0.0)) /
        blur_vec;
    // Quartic polynomial fit to:
    //   x/2 + exp(-x^2/2)/sqrt(2*pi) + x/2 * erf(x/sqrt(2))
    // subject to y(0)=0, y'(0)=0, y(1)=1/2, y'(1)=1
    const float3 c = float3(-0.3635, 0.727, 0.1365);
    const float4 poly = ((c.xxxx * x_n + c.yyyy) * x_n + c.zzzz) * x_n * x_n * min(range, blur_vec);
    // Exploit point symmetry around the rectangle center.
    const float4 transition = lerp(poly, range - poly, step(center, px_square));
    // Pick linear or transitional region per edge.
    const float4 res = lerp(lin, transition, step(0.5 * (range - blur_vec), dist_to_center));
    return (res.z - res.x) * (res.w - res.y);
}

// ---------------------------------------------------------------------------
// LCD parameters (shared.inc :: calculate_lcd_params), computed per-pixel.
// Everything here except tx_coord is constant across the frame, so evaluating
// it in the pixel shader is equivalent to the original per-vertex + interpolate.
// ---------------------------------------------------------------------------

struct LcdParams {
    float4 rect1;          // lcd_subpx_rect1
    float4 rect2;          // lcd_subpx_rect2
    float2 subpx_off;      // subpx_offset_in_px
    float2 tx_to_px;       // output_size / source_size
    float2 tx_orig_offs;   // tx_orig_offs
    float  blur;           // eff_blur_in_px (accurate mode)
    float  half_px;        // half_px_size   (fast mode)
};

LcdParams make_lcd_params(float2 tex_coord, float2 source_size, float2 output_size) {
    LcdParams p;

    const float use_subpx = AUTH_GBC_SUBPX ? 1.0 : 0.0;

    // Subpixel stripe direction per layout (rotation assumed 0).
    // Equivalent to the original rot_corr[] lookup, but written without
    // integer/bitwise ops so it compiles on the DX9 / ps_3_0 target.
    //   0 = RGB (horizontal), 1 = RGB vertical, 2 = BGR (horizontal), 3 = BGR vertical
    float2 subpx_dir;
    if      (AUTH_GBC_SUBPX_ORIENTATION == 1) subpx_dir = float2( 0.0,  1.0);
    else if (AUTH_GBC_SUBPX_ORIENTATION == 2) subpx_dir = float2(-1.0,  0.0);
    else if (AUTH_GBC_SUBPX_ORIENTATION == 3) subpx_dir = float2( 0.0, -1.0);
    else                                      subpx_dir = float2( 1.0,  0.0);
    p.subpx_off = use_subpx / 3.0 * subpx_dir;

    p.tx_to_px = output_size / source_size;

    // As determined by counting pixels on a reference photo.
    const float2 subpx_ratio = float2(0.296, 0.910);
    const float2 notch_ratio = float2(0.115, 0.166);

    // Subpixel and notch sizes scale with the brightness parameter; the
    // maximally bright targets are hand-tuned.
    const float2 lcd_subpx_size = p.tx_to_px * lerp(subpx_ratio, float2(0.75, 0.93), AUTH_GBC_BRIG);
    const float2 notch_size     = p.tx_to_px * lerp(notch_ratio, float2(0.29, 0.17), AUTH_GBC_BRIG);

    p.rect1 = float4(0.0, 0.0, lcd_subpx_size.x, lcd_subpx_size.y - notch_size.y);
    p.rect2 = float4(notch_size.x, lcd_subpx_size.y - notch_size.y, lcd_subpx_size.x, lcd_subpx_size.y);
    p.tx_orig_offs = (p.tx_to_px - lcd_subpx_size) * 0.5;

    // Blur strength is isotropic; use the most limiting dimension.
    const float min_px = min(p.tx_to_px.x, p.tx_to_px.y);
    p.blur = AUTH_GBC_BLUR * min_px * 0.5;

    // Fast mode grows the pixel square and normalizes (box filter); the 0.7
    // factor compensates for the sharper-looking Gaussian at equal radius.
    const float eff_blur_fast = 0.7 * AUTH_GBC_BLUR * min_px * 0.5;
    p.half_px = 0.5 * clamp(1.0 + eff_blur_fast, 1.0, min_px);

    return p;
}

// ---------------------------------------------------------------------------
// Subpixel coverage / pixel color  (from the main slang shaders)
// ---------------------------------------------------------------------------

// Accurate: two Gaussian-smoothed rectangles compose the notched subpixel.
float subpx_coverage_acc(LcdParams p, float4 px_square, float2 subpx_orig) {
    return intersect_blurred_rect_area(px_square, subpx_orig.xyxy + p.rect1, p.blur) +
           intersect_blurred_rect_area(px_square, subpx_orig.xyxy + p.rect2, p.blur);
}

float3 pixel_color_acc(LcdParams p, float2 tx_orig) {
    return float3(
        subpx_coverage_acc(p, float4(-p.subpx_off - 0.5, -p.subpx_off + 0.5),
                           tx_orig + float2(p.tx_orig_offs.x - p.tx_to_px.x / 3.0, p.tx_orig_offs.y)),
        subpx_coverage_acc(p, float4(-0.5, -0.5, 0.5, 0.5),
                           tx_orig + p.tx_orig_offs),
        subpx_coverage_acc(p, float4(p.subpx_off - 0.5, p.subpx_off + 0.5),
                           tx_orig + float2(p.tx_orig_offs.x + p.tx_to_px.x / 3.0, p.tx_orig_offs.y)));
}

// Fast: sharp box-filter rectangles, sized by half_px.
float subpx_coverage_fast(LcdParams p, float4 px_square, float2 subpx_orig) {
    return intersect_rect_area(px_square, subpx_orig.xyxy + p.rect1) +
           intersect_rect_area(px_square, subpx_orig.xyxy + p.rect2);
}

float3 pixel_color_fast(LcdParams p, float2 tx_orig) {
    const float h = p.half_px;
    return float3(
        subpx_coverage_fast(p, float4(-p.subpx_off - h, -p.subpx_off + h),
                            tx_orig + float2(p.tx_orig_offs.x - p.tx_to_px.x / 3.0, p.tx_orig_offs.y)),
        subpx_coverage_fast(p, float4(-h, -h, h, h),
                            tx_orig + p.tx_orig_offs),
        subpx_coverage_fast(p, float4(p.subpx_off - h, p.subpx_off + h),
                            tx_orig + float2(p.tx_orig_offs.x + p.tx_to_px.x / 3.0, p.tx_orig_offs.y)));
}

// ---------------------------------------------------------------------------
// Main pixel shader
// ---------------------------------------------------------------------------

float4 PS_AuthenticGBC(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
    const float2 source_size     = AUTH_GBC_RES;
    const float2 source_size_inv = 1.0 / source_size;
    const float2 screen_size     = ReShade::ScreenSize;

    // Work out the on-screen rectangle the console image occupies.
    // Fill screen: the whole backbuffer. Centered: aspect-correct, centred, with
    // untouched borders (for a GBC image pillarboxed on a wider screen).
    float2 rect_min, content_size;
    if (AUTH_GBC_FIT == 0) {
        rect_min     = float2(0.0, 0.0);
        content_size = screen_size;
    } else {
        // Target display aspect (width / height) of the content rectangle.
        float target_aspect;
        if      (AUTH_GBC_ASPECT == 1) target_aspect = 4.0 / 3.0;
        else if (AUTH_GBC_ASPECT == 2) target_aspect = AUTH_GBC_ASPECT_CUSTOM;
        else                           target_aspect = source_size.x * source_size_inv.y; // square pixels

        // Largest rectangle of that aspect that fits on screen.
        if (screen_size.x / screen_size.y > target_aspect) {
            content_size.y = screen_size.y;
            content_size.x = screen_size.y * target_aspect;
        } else {
            content_size.x = screen_size.x;
            content_size.y = screen_size.x / target_aspect;
        }

        // Optional integer vertical scale (keeps rows pixel-exact); the width
        // then follows the chosen display aspect.
        if (AUTH_GBC_FIT_INTEGER) {
            float vscale = max(floor(content_size.y * source_size_inv.y), 1.0);
            content_size.y = vscale * source_size.y;
            content_size.x = content_size.y * target_aspect;
        }

        rect_min = floor((screen_size - content_size) * 0.5) + AUTH_GBC_OFFSET;
    }
    const float2 rect_max = rect_min + content_size;

    const float2 pixel_pos = texcoord * screen_size;

    // Outside the console image (the borders): leave the original pixels untouched.
    if (AUTH_GBC_FIT != 0 &&
        (pixel_pos.x <  rect_min.x || pixel_pos.y <  rect_min.y ||
         pixel_pos.x >= rect_max.x || pixel_pos.y >= rect_max.y)) {
        return tex2D(AuthGBCSource, texcoord);
    }

    // Coordinates local to the console image, plus the UV remap needed to sample
    // the image where it actually sits on the backbuffer.
    const float2 local_uv    = (pixel_pos - rect_min) / content_size; // 0..1 across the image
    const float2 rect_min_uv = rect_min / screen_size;
    const float2 rect_uv     = content_size / screen_size;

    const LcdParams p = make_lcd_params(local_uv, source_size, content_size);

    // tx_coord = local_uv * source_size  (the only position-dependent value).
    const float2 tx_coord   = local_uv * source_size;
    const float2 tx_coord_i = floor(tx_coord);              // integer part (>= 0)
    const float2 tx_coord_f = tx_coord - tx_coord_i;        // fractional part

    // Pick the four nearest source texels.
    const float2 tx_coord_off = step(float2(0.5, 0.5), tx_coord_f) * 2.0 - 1.0;
    float2 tx_coord_offs[4];
    tx_coord_offs[0] = float2(0.0, 0.0);
    tx_coord_offs[1] = float2(tx_coord_off.x, 0.0);
    tx_coord_offs[2] = float2(0.0, tx_coord_off.y);
    tx_coord_offs[3] = tx_coord_off;

    // Console-local UV -> backbuffer UV (maps the sample into the content rectangle).
    float3 samples[4];
    samples[0] = tex2D(AuthGBCSource, rect_min_uv + (tx_coord_i + tx_coord_offs[0] + 0.5) * source_size_inv * rect_uv).rgb;
    samples[1] = tex2D(AuthGBCSource, rect_min_uv + (tx_coord_i + tx_coord_offs[1] + 0.5) * source_size_inv * rect_uv).rgb;
    samples[2] = tex2D(AuthGBCSource, rect_min_uv + (tx_coord_i + tx_coord_offs[2] + 0.5) * source_size_inv * rect_uv).rgb;
    samples[3] = tex2D(AuthGBCSource, rect_min_uv + (tx_coord_i + tx_coord_offs[3] + 0.5) * source_size_inv * rect_uv).rgb;

    float3 res;
    if (AUTH_GBC_MODE == 0) {
        // ---- Accurate (matches authentic_gbc.slang / _single_pass.slang) ----
        // Linearize inline (gamma 2.2).
        samples[0] = pow(samples[0], 2.2);
        samples[1] = pow(samples[1], 2.2);
        samples[2] = pow(samples[2], 2.2);
        samples[3] = pow(samples[3], 2.2);

        res = pixel_color_acc(p, (tx_coord_offs[0] - tx_coord_f) * p.tx_to_px) * samples[0] +
              pixel_color_acc(p, (tx_coord_offs[1] - tx_coord_f) * p.tx_to_px) * samples[1] +
              pixel_color_acc(p, (tx_coord_offs[2] - tx_coord_f) * p.tx_to_px) * samples[2] +
              pixel_color_acc(p, (tx_coord_offs[3] - tx_coord_f) * p.tx_to_px) * samples[3];

        return float4(pow(res, 1.0 / 2.2), 1.0);
    } else {
        // ---- Fast (matches authentic_gbc_fast.slang + to_lin_fast.slang) ----
        // Linearize inline (gamma 2.0 approximation: s * s).
        samples[0] = samples[0] * samples[0];
        samples[1] = samples[1] * samples[1];
        samples[2] = samples[2] * samples[2];
        samples[3] = samples[3] * samples[3];

        res = (pixel_color_fast(p, (tx_coord_offs[0] - tx_coord_f) * p.tx_to_px) * samples[0] +
               pixel_color_fast(p, (tx_coord_offs[1] - tx_coord_f) * p.tx_to_px) * samples[1] +
               pixel_color_fast(p, (tx_coord_offs[2] - tx_coord_f) * p.tx_to_px) * samples[2] +
               pixel_color_fast(p, (tx_coord_offs[3] - tx_coord_f) * p.tx_to_px) * samples[3]) /
              (4.0 * p.half_px * p.half_px);

        return float4(sqrt(res), 1.0);
    }
}

// ---------------------------------------------------------------------------

technique AuthenticGBC <
    ui_label = "Authentic GBC";
    ui_tooltip = "Authentic Game Boy Color subpixel rendering (port of fishku's CC0 slang shader).";
> {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = PS_AuthenticGBC;
    }
}

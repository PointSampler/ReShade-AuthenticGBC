# Authentic GBC for ReShade

A ReShade port of **fishku's "Authentic GBC"** shader. It recreates the look of a
Game Boy Color LCD by rendering the individual RGB subpixels — including the
characteristic little "notch" (dog-ear) on each one — using analytical pixel
coverage for clean, sharp anti-aliasing.

The original is a [libretro slang shader](https://github.com/libretro/slang-shaders);
this port packages it as a single self-contained `.fx` so it can be used in any
game or emulator that supports ReShade, on any rendering backend.

<img width="2560" height="1440" alt="Authentic GBC for ReShade running on Mina the Hollower - Menu" src="https://github.com/user-attachments/assets/e8788880-ac7a-4581-b4a6-5424b52bdbf9" />

<img width="2560" height="1440" alt="Authentic GBC for ReShade running on Mina the Hollower - Ingame" src="https://github.com/user-attachments/assets/6847cf4d-b1ea-4a15-8a46-1d41a811efcb" />

*The screenshots show Mina the Hollower © Yacht Club Games, used under their
[video/content policy](https://www.yachtclubgames.com/video-policy/) to demonstrate the shader.*

## Features

- Authentic GBC subpixel rendering with the signature notched subpixels.
- Adjustable brightness, anti-banding smoothing, and optional subpixel offset.
- Selectable subpixel layout (RGB / BGR, horizontal or vertical).
- Two quality modes: **Accurate** (Gaussian-smoothed coverage) and **Fast**
  (cheaper box-filter approximation).
- Works on any source resolution, not just 160×144 — usable for NES, SNES,
  Genesis, GBA and more.
- Two display modes: **Fill screen** for fullscreen content and **Centered**
  for a console image pillarboxed on a wider display, with untouched borders.

## Requirements

- A game or emulator with [ReShade](https://reshade.me) installed.

## Installation

1. Install ReShade into your game/emulator, choosing the rendering API it uses
   (Direct3D, OpenGL, or Vulkan).
2. Copy `AuthenticGBC.fx` into your `reshade-shaders\Shaders\` folder.
3. Launch the game, open the ReShade overlay (default `Home` key), and enable
   **Authentic GBC** in the technique list.

## Settings

All controls appear under the **Authentic GBC** category in the ReShade overlay
and can be changed live.

| Setting | Default | Description |
| --- | --- | --- |
| **Source resolution (px)** | `160 x 144` | Native pixel resolution of the source content; the LCD grid is built from this. Set it to match what you're applying the shader to (see the per-system table below). |
| **Content scaling** | `Fill screen` | `Fill screen`: the source is assumed to cover the whole screen. `Centered`: an aspect-correct image sits in the middle with untouched borders. |
| **Display aspect** | `Square pixels` | *Centered only.* `Square pixels` (Game Boy / GBC / GBA), `4:3 (CRT)` (NES / SNES / Genesis), or `Custom`. |
| **Custom aspect (w / h)** | `1.3333` | *Centered only.* Used when Display aspect is `Custom` (e.g. `1.3333` = 4:3). |
| **Snap to integer scale** | `On` | *Centered only.* Locks the vertical scale to whole pixels; match an emulator using integer scaling. Turn off if your emulator scales to fit exactly. |
| **Center nudge (px)** | `0, 0` | *Centered only.* Fine offset if the image isn't perfectly centered. |
| **Add brightness** | `0.60` | Brightens the image by enlarging each subpixel. |
| **Anti-banding smoothing** | `0.30` | Softens subpixel edges to reduce banding. |
| **Enable subpixel rendering** | `Off` | Adds a horizontal/vertical RGB offset within each pixel. |
| **Subpixel layout** | `RGB` | Subpixel arrangement: RGB, RGB vertical, BGR, or BGR vertical. |
| **Quality** | `Accurate` | `Accurate` = Gaussian coverage (matches the original two-pass preset). `Fast` = box-filter approximation (lighter; gamma 2.0). |

## Display modes

ReShade runs on the final rendered frame and has no knowledge of an emulator's
native framebuffer or the games internal resolution, so you have to tell
the shader where the image is via these two modes.

**Fill screen** assumes the source image covers the entire backbuffer. Use it for
fullscreen pixel-art games (Shovel Knight, Mina the Hollower, Stardew Valley) or an
emulator stretched to fill the screen. Set **Source resolution** to the game's
internal pixel resolution so the grid lands on real pixels. For best results the
content should be nearest-neighbour scaled.

**Centered (pillarbox)** places an aspect-correct image in the middle of the screen
and leaves the borders untouched — so black bars stay black instead of being filled
with subpixels. Use it when emulating a console that doesn't fill a widescreen
display. Set **Source resolution** and **Display aspect** for your system, keep
**Snap to integer scale** on, and set your emulator to integer / pixel-perfect
scaling so the shader's rectangle and the emulator's image coincide. If your emulator
stretches to fit instead, turn integer snap off. Small positioning differences can be
corrected with **Center nudge**.

> Alignment note: in Centered mode the shader samples the source from where it
> *computes* the rectangle to be (a centred, aspect-correct, optionally
> integer-scaled rect). This lines up automatically when the emulator also
> integer-scales and centers. If the emulator draws at a different fixed scale, the
> two rectangles won't coincide — set the emulator to integer scaling so they match.

### Per-system reference (Centered mode)

| System | Source resolution | Display aspect |
| --- | --- | --- |
| Game Boy / Game Boy Color | `160 x 144` | Square pixels |
| Game Boy Advance | `240 x 160` | Square pixels |
| NES | `256 x 240` | 4:3 (CRT) |
| SNES | `256 x 224` | 4:3 (CRT) |
| Genesis / Mega Drive | `320 x 224` | 4:3 (CRT) |

## Credits

- **Original shader:** "Authentic GBC" (v2.2) by **fishku**
  (GitHub: [@fishcu](https://github.com/fishcu)), released into the public domain
  under CC0. Part of the [libretro slang-shaders](https://github.com/libretro/slang-shaders)
  project (`handheld/shaders/authentic_gbc/`).
- **Pixel-coverage helper** (`coverage.inc`): also by fishku, from the same
  project (`misc/shaders/coverage/`).
- **ReShade (.fx) port:** PointSampler, using Claude Opus 4.8.

If you enjoy the shader, the credit really belongs to fishku — please point people
to the original project.

## License

The original shader is dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). In keeping with the
original, this port is also released under **CC0 1.0** — do whatever you like with
it. See the `LICENSE` file for the full text.

# App icon: 藏 on a lotus throne — design

**Intent.** The owner wants a better icon: keep the 藏 glyph, add a lotus, give the text depth and shading,
and have a tinted version. The current icon is a single flat PNG (Song-style 藏, brown on sepia).

**Goals.** 藏 stays the subject and reads clearly at home-screen size; a lotus throne beneath it; real depth
(layered, shaded); good light, dark and tinted appearances.
**Non-goals.** Changing the app name, in-app artwork, or the reader palette.
**Anti-goals.** A lotus that hides or crowds 藏; a tinted version where 藏 fades into the background.

## Approaches

- **A. Icon Composer layered icon (`AppIcon.icon`) — chosen.** Vector layers (sepia background, 藏, lotus);
  iOS 26 renders Liquid Glass depth, inter-layer shadows and specular edges, and derives dark / tinted / clear
  from one file, with per-appearance colours. Previews render headlessly with `ictool`.
- B. Three hand-shaded PNGs in the asset catalog. Full control of baked shading, but shown flat inside the
  system glass and the tinted grayscale tends to look muddy. Not chosen.

Layout: of three rendered candidates (seat, halo, pedestal) the owner picked **pedestal**: 藏 above a small
lotus throne.

## Design

- **Layers, back to front:** sepia gradient fill → 藏 group → lotus group (back petals and front petals as
  separate layers, so the throne has its own depth).
- **藏:** the Songti SC Bold outline as an SVG path, about 40% of the canvas height (the prototype the owner chose: a 560 pt outline drawn at 0.72), set above centre.
  Brown `#4A3426` in light mode; warm ivory in dark mode.
- **Lotus:** six fanned back petals in a pale-to-mid rose gradient, five upright front petals in mid-to-deep rose,
  in the lower part of the canvas. Its top just reaches the foot of 藏 without covering any stroke.
- **Background:** light mode is a sepia vertical gradient (the reader's paper colour); dark mode is a deep brown-black gradient.
- **Tinted:** 藏 must stay the brightest, clearest element. Raise its contrast against the lotus and fill
  (e.g. a per-appearance fill or lower lotus opacity in tinted), checked in `ictool` TintedDark/TintedLight renders.

## Builder's calls (mine, open to correction)

- **Source of truth:** a generator script (`Scripts/make-app-icon.py`) writes `DzzReader/AppIcon.icon`. The
  committed `.icon` can still be opened and tweaked in Icon Composer.
- **Old icon:** the old `AppIcon.appiconset` is removed so the two don't clash under the name `AppIcon`;
  `ASSETCATALOG_COMPILER_APPICON_NAME` stays `AppIcon`.
- **Verification:** check Default, Dark, TintedLight, TintedDark and a small (60 pt) render for legibility, then
  build and install on the simulator to see it on the home screen.

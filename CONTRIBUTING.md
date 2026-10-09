# Contributing to Paint Again

Thanks for helping. This document is everything you need to build the app,
find your way around the code and get a change merged.

## Ways to help

- **Report a bug** — use the [bug report form](https://github.com/HaoCherHong/paint-again/issues/new?template=bug_report.yml). Include your macOS version, the app version and steps to reproduce; a screenshot or screen recording helps a lot.
- **Suggest a feature** — use the [feature request form](https://github.com/HaoCherHong/paint-again/issues/new?template=feature_request.yml). Read [Product scope](#product-scope) first.
- **Translate** — the UI ships in English and Traditional Chinese. New languages are welcome; see [Localization](#localization).
- **Send a pull request** — for anything larger than a small fix, open an issue first so we can agree on the approach before you spend time on it.

## Product scope

Paint Again is a simple drawing app with a fixed layout: a menu strip with
Save / Share / Undo / Redo, a ribbon of tool groups, floating Size / Opacity
sliders and a Layers card over a solid Background.

- New UI should fit that layout and feel familiar rather than novel. For
  keyboard behaviour, follow Photoshop's conventions.
- **Out of scope**: generative / AI features (assistants, image generation,
  generative fill or erase), accounts and sign-in, cloud sync, analytics,
  anything that makes a network connection. The app is fully offline and
  that is a promise to users.
- Keep it simple. Paint Again is not trying to become a full image editor.

## Development setup

Requirements:

- macOS 14 or later (macOS 26 to see Liquid Glass)
- Xcode 26 (Swift 6 toolchain and the macOS 26 SDK); the code builds in Swift 5 language mode

```bash
git clone https://github.com/HaoCherHong/paint-again.git
cd paint-again/app
scripts/build.sh
open "build/Paint Again.app"
```

| Command | Purpose |
| --- | --- |
| `scripts/build.sh` | Release build → `build/Paint Again.app` |
| `scripts/build.sh debug` | Debug build |
| `PAINT_UNIVERSAL=1 scripts/build.sh` | arm64 + x86_64 build |
| `scripts/sign-sandboxed.sh` | Re-sign the build with the App Sandbox entitlements (ad-hoc) to test sandbox behaviour |
| `scripts/package-release.sh` | Maintainers: signed, notarised zip for GitHub Releases (dry run without a Developer ID) |
| `scripts/gen-app-icon.sh` | Regenerate `Resources/AppIcon.icns` |

There is no Xcode project. To work in Xcode, open `app/Package.swift`
(`xed app/`); run the `Paint` scheme for debugging, but use `scripts/build.sh`
when you need the real `.app` bundle.

## Code layout

All app code is under `app/`:

| Path | What lives there |
| --- | --- |
| `Sources/Paint/Model/` | `PaintDocument` (NSDocument), `Layer`, `Bitmap`, `ToolState`, `ToolKind` |
| `Sources/Paint/Tools/` | One class per tool, all subclasses of `Tool` |
| `Sources/Paint/Engine/` | `FloodFill`, `ShapePaths`, `BrushPainter` |
| `Sources/Paint/Views/` | `MainWindowController` (window chrome), `Ribbon/`, `Canvas/`, Layers panel, status bar, sliders, dialogs |
| `Sources/Paint/Resources/*.lproj/` | Localized strings |
| `Sources/Paint/DebugSelfTest.swift` | Headless self-test (below) |
| `scripts/` | Build, signing, packaging and icon scripts |
| `Info.plist`, `Paint.entitlements`, `PrivacyInfo.xcprivacy` | Bundle inputs copied by `scripts/build.sh` |

The website lives in `web/` (Astro 5 + Tailwind 4): `npm ci && npm run dev`
inside `web/`.

## Conventions

- **AppKit, programmatic UI.** No storyboards, xibs or SwiftUI.
- **Image coordinates** are top-left-origin pixels. `Bitmap` contexts are pre-flipped so tools draw in pixel space directly; `CanvasView` is a flipped NSView. Use `Bitmap.draw(_:in:)` / `CanvasView.drawImage` to draw CGImages upright.
- **Every pixel edit is undoable.** Go through `PaintDocument.performLayerChange`, or `beginLayerEdit` + `commitLayerEdit` (single-layer undo), or `performStructuralChange` (canvas size, layer list, background).
- **The Background is a solid colour, not a layer.** `layers[0]` is an ordinary transparent layer. Never fill holes or erased areas with Color 2.
- **Painting tools** draw into `CanvasView.strokeBuffer` and composite on mouse-up with the user's opacity; the tool's `drawOverlay` draws the footprint outline.
- **Comments describe what the code is**, not its history; the history belongs in commit messages.
- Keep the build at **zero warnings**.

### Localization

Strings live in `Sources/Paint/Resources/<lang>.lproj/Localizable.strings`.
Keys are the English text; look them up with `L("…")`. When you add a UI
string, add it to **every** `.lproj` file in the same change. English uses US
spelling (Color, Watercolor).

To add a language, copy `en.lproj` to `<code>.lproj` and translate the
values. Check it with:

```bash
"build/Paint Again.app/Contents/MacOS/Paint" -AppleLanguages '(<code>)'
```

## Verifying a change

Before opening a pull request, from `app/`:

```bash
scripts/build.sh     # must print only "Built build/Paint Again.app"
PAINT_SELFTEST=1 PAINT_SNAPSHOT=/tmp/paint.png PAINT_QUIT=1 PAINT_SNAPSHOT_DELAY=6 \
  "build/Paint Again.app/Contents/MacOS/Paint"
```

The self-test drives every tool with synthetic events on a fresh document and
prints `SELFTEST …` lines; each must read `true` or the expected value. Open
`/tmp/paint.png` and look for layout or rendering regressions. Add
`PAINT_APPEARANCE=light` to check the light theme.

Useful environment variables:

| Variable | Effect |
| --- | --- |
| `PAINT_SELFTEST=1` | Drive every tool with synthetic events, print `SELFTEST …` lines |
| `PAINT_SNAPSHOT=<png>` | Render the window to a PNG after `PAINT_SNAPSHOT_DELAY` seconds |
| `PAINT_QUIT=1` | Quit after the snapshot |
| `PAINT_APPEARANCE=light` | Force the light appearance |
| `PAINT_OPEN_SETTINGS=1` | Open the Settings window (with `PAINT_SNAPSHOT_KEYWINDOW=1` to snapshot it) |
| `PAINT_EVENT_LOG=1` | Log canvas mouse events to stderr |

Mouse behaviour (cursors, hover outlines, drags) cannot be fully tested
headlessly — try it by hand and say what you checked in the pull request.

## Pull requests

1. Fork the repo and branch off **`develop`** (app changes) or **`web`** (website changes). `main` only moves at releases.
2. Keep each pull request focused on one change. Unrelated clean-ups go in their own PR.
3. Run the checks in [Verifying a change](#verifying-a-change). CI builds the app on every PR.
4. For visible changes, attach before / after screenshots, ideally in both light and dark.
5. Write commit messages in the imperative mood ("Add …", "Fix …") with a short summary line.

By contributing you agree that your contribution is licensed under the
project's [MIT License](LICENSE).

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Released code; App Store builds and GitHub releases are cut from here |
| `develop` | App development; merges into `main` at each release |
| `web` | The website; pushing it deploys [paintagain.app](https://paintagain.app) |

## Questions

Open a [discussion or issue](https://github.com/HaoCherHong/paint-again/issues)
— there are no silly questions.

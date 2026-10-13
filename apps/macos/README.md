> Native CI and distribution: see [docs/NATIVE-CICD.txt](../../docs/NATIVE-CICD.txt).
> Historical visual-stage notes below describe the original scaffold; production now uses C++/Socket.IO.

# Paloma Morse — native macOS client (SwiftUI)

Native presentation layer for macOS 26+, built with Xcode 27 and the macOS 27 SDK.
No Electron, WebView, Node.js or browser audio. Sound is produced only by the shared
C++ engine through an `AudioService` adapter (owned by the integration branch).

## Open and run

Open `apps/macos/PalomaMorse/PalomaMorse.xcodeproj` in Xcode 27, scheme **PalomaMorse**,
destination **My Mac**, then ⌘R. Tests: ⌘U.

Command line:

```sh
xcodebuild -project apps/macos/PalomaMorse/PalomaMorse.xcodeproj -scheme PalomaMorse \
  -destination 'platform=macOS,arch=arm64' build
xcodebuild -project apps/macos/PalomaMorse/PalomaMorse.xcodeproj -scheme PalomaMorse \
  -destination 'platform=macOS,arch=arm64' test
```

| Setting | Value |
| --- | --- |
| Deployment target | macOS 26.0 (macOS 27 APIs only behind `#available`) |
| Bundle ID | `com.paloma.morse.native-preview` (provisional, distinct from the shipping `com.paloma.morse`) |
| Sandbox | App Sandbox on, no entitlements yet |
| Swift | Swift 5 mode, default actor isolation `MainActor` |

## What runs where

| Build | Audio | Network |
| --- | --- | --- |
| Debug | `DemoAudioService`: engine-shaped events, **no sound**, labelled once in the window subtitle "Демо · без звука" | `UnavailableNetworkService` (sign-in disabled, explained on the sign-in card) |
| Release | `UnavailableAudioService`: Start disabled with the reason | `UnavailableNetworkService` |
| `-PalomaFixture …` (Debug) | Fixture state + demo engine, subtitle "Превью-данные · без звука" | `PreviewNetworkService` (no socket) |

Launch arguments (scheme → Run → Arguments, or after `--args`):

- `-PalomaFixture <name>` — deterministic state; names are in `PreviewSupport/PreviewFixtures.swift`
- `-PalomaAudio demo|unavailable`
- `-PalomaAppearance light|dark`
- `-PalomaWindowSize 1000x700`

## Source layout (`PalomaMorse/`)

| Folder | Contents |
| --- | --- |
| `App/` | `@main` (main window, History window, Settings), composition root (`AppModel`), root view with the toolbar header and mode tabs, menu commands, launch options |
| `Domain/` | Catalog lookup, settings store, sequence generation, reception / transmission / radio models, history. No SwiftUI. |
| `Adapters/` | `AudioService` and `NetworkService` boundaries, `AudioCoordinator` (single event consumer), unavailable stubs |
| `PreviewSupport/` | Demo engine, fixtures, canvas previews. Not a live adapter. |
| `DesignSystem/` | Tokens, mode tabs, parameter column, "− value +" stepper, Start/Stop, letter cards and answer keys, pattern drawing, rhythm tape |
| `Features/` | Reception (column + work area + results), Transmission, Radio (Эфир), History, Settings |
| `Resources/morse.v1.json` | Symlink to `shared/catalog/morse.v1.json`; Xcode copies the real file into the bundle |

## Review tools

```sh
apps/macos/Tools/check-stability.sh                 # every fixture at 1000x700 and 1440x900, app must survive 6 s
apps/macos/Tools/capture-screenshots.sh [dir] [fixture…]   # needs Screen Recording permission
swift apps/macos/Tools/compare-sheet.swift legacy.png native.png out.png "caption"   # v0.4.20 vs native
```

`PALOMA_SIZES` and `PALOMA_APPEARANCES` narrow the capture (e.g. `PALOMA_SIZES=900x620`).

Both build an isolated review copy into a temporary DerivedData under the bundle identifier
`com.paloma.morse.native-review` (`PALOMA_REVIEW_BUNDLE_ID` overrides it), so they use their own
defaults domain and never touch the settings, saved state or process of a copy you are running.
Only the PID each script started is terminated; windows are found by that PID. During capture the
review copy comes to the front; switching Spaces makes a capture miss its window, which the script
reports as `NOT CAPTURED` (exit status 1).

## Layout

Visual stage 2 copies the released Paloma v0.4.20 layout: a compact toolbar header (key indicator,
name, tone and volume with values, History, Settings), the tabs Приём · Передача · Эфир, and in
Reception/Transmission a parameter column with Start/Stop pinned at its bottom. There is no
NavigationSplitView, sidebar or inspector any more.

## Known platform issue (macOS 27 beta)

In stage 1 AppKit aborted with "more Update Constraints in Window passes than there are views" when
size-dependent content took part in `NavigationSplitView` column sizing next to an open inspector.
Stage 2 has neither, and `Tools/check-stability.sh` keeps guarding the fixtures. If such a loop
reappears, see `docs/native-clients/handoffs/macos.txt` for what triggered it before.

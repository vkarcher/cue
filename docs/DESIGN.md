# Cue: design decisions

Decisions accepted by the owner. Do not reopen them without a new request.

## Product

- Name: **Cue** (the signal a control room gives to start an action), chosen on 2026-10-18 over the first name Régie. Each page sets the window title and a subtitle with its state, like a native macOS app.
- The menu bar item stays a plain switch: "Automatic activation", "Open Cue", "Quit". Everything else lives in the window.
- The TV remote controls the television only: power, inputs, navigation, playback, volume. No TV app launcher: apps are used through the Apple TV on HDMI 1.
- Copy is written in English in the code and translated in the String Catalogs of `Cue/Resources`; the app follows the system language. Every new string needs its French entry.

## Icon

- The mark: Wi-Fi waves rising from a game controller cross. The app is about connection stability in game first, the television second, so no television in the icon.
- App icon: the white mark on an orange gradient (#FFB340 to #E8530C). Rejected on 2026-10-18: tally light, play button, television screen, flatline, ring; and the fuchsia, graphite, blue, teal and red versions of the chosen mark.
- Menu bar: the controller cross alone, monochrome template image, with a hollow center so it does not read as a plus sign. No Wi-Fi waves: next to the system Wi-Fi item they read as the Mac's own network status (owner, 2026-10-18). A dot in the top right corner while in game, the cross dimmed when paused or not installed.
- The app icon is the Icon Composer document `Cue/Resources/AppIcon.icon`: the gradient fill, the waves and the cross as two SVG layers with specular and translucency, so macOS derives the dark and tinted variants. Edit it in Icon Composer. The menu bar cross is drawn in `CueApp.menuBarImage`.

## Disk image

- The DMG window shows Cue and a link to Applications side by side with an orange arrow, "Drag Cue to Applications" above and the next step below. The background is `scripts/dmg/background.tiff` (1x and 2x), rendered from `scripts/dmg/background.svg`.
- The background is a warm mid-tone (#7A6A60 around the labels) because Finder draws icon labels in black or white depending on the appearance; both stay readable on it.
- The mounted volume uses the app icon.

## Window

- Sidebar with three destinations: Remote, Game session, Diagnostics. The sidebar footer shows the session state.
- Pattern source: settings sidebars with device rows and a status dot (mobbin: Pipedrive, Revolut Business, Kraken).

## Remote: direction C

Chosen among three SwiftUI prototypes: A "Galet" (ring d-pad object), B "Console" (cross d-pad, volume rocker, source list), C "Sources". The owner rejected the classic remote look of A and B; the prototypes were removed once C was built.

Top to bottom:

1. Window title "Remote", subtitle with the model and power state. The power button is the toolbar's primary action: glass prominent, red when on, green when off.
2. The four inputs as tiles, with the labels the television reports. The selected input has a tinted fill and an accent border. The input used for GeForce NOW carries a game controller symbol and "· game".
3. A touchpad: one arrow per 48 points of swipe, a click without travel is OK. Keyboard shortcuts are shown inside it: arrows, Return for OK, Escape for back, Space for play/pause, + and − for volume.
4. A floating glass capsule at the bottom: back, home, play/pause, then mute, volume slider and value. Its buttons are borderless, since glass never sits on glass.

When the television is off, every control is dimmed and the touchpad reads "The television is off".

## Visual language

- Native macOS 26: `NavigationSplitView`, grouped `Form` for Game session and Diagnostics, `ContentUnavailableView` for the unpaired remote.
- Liquid Glass only on the navigation layer: the toolbar and the remote's floating control bar. Content (tiles, touchpad, forms) uses system fills, never glass. Only the power button is tinted.
- Tiles corner radius 14, touchpad 22, on `fill.quaternary`.
- Logs: form sections with a monospaced caption, selectable, a "Copy" button in the header, opened scrolled to the newest entry.

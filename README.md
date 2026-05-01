# ShortcutHUD

A macOS keyboard-shortcut HUD. Press a global hotkey and a panel slides in showing every keyboard shortcut available in the frontmost app, plus the macOS system shortcuts — searchable, multi-column, light/dark adaptive.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

1. Double-click `ShortcutHUD.app` to launch it (or build from source — see below)
2. A `⌘` icon appears in your menu bar
3. Grant **Accessibility** and **Input Monitoring** permission when prompted

## Default Hotkey

`⌘⌥⌃⇧ /` (the hyper-key plus forward slash). Configurable in Settings.

## What You See

When you press the hotkey, the HUD captures the frontmost app, walks its menu structure via the Accessibility API, and lists every shortcut grouped by menu (File, Edit, View, …). A separate **macOS** pane lists the system symbolic hotkeys.

| Action | Key |
|--------|-----|
| Filter | type to fuzzy-match against title and path |
| Move selection | `↑` / `↓` |
| Activate selected | `↩` |
| Dismiss | `⎋` or click outside |

Activating an app shortcut invokes the corresponding menu item in the captured app. System shortcuts are listed for reference only in v1 (no activation).

## Resizing & Repositioning

The HUD is resizable from any edge and draggable from the background (anywhere that isn't a row or the search field). The size and position persist across launches.

## Settings

Click the menu-bar icon → **Settings…**

- **Keyboard Shortcut** — record any combination
- **Accessibility** — status + grant button
- **Input Monitoring** — status + grant button
- **Auto-update** — check for new versions on a configurable schedule

## Permissions

### Accessibility (required)

Used to read the menu structure of the captured app and to invoke menu items. Prompted automatically on first launch.

Grant in: **System Settings → Privacy & Security → Accessibility**

### Input Monitoring (required)

Used by the global hotkey listener (a `CGEventTap`). Prompted automatically on first launch.

Grant in: **System Settings → Privacy & Security → Input Monitoring**

The menu-bar icon shows a `⚠️` glyph if the event tap failed to install (typically because Input Monitoring is missing). After granting, the icon clears automatically — no relaunch required.

## Coexistence with other event-tap tools

ShortcutHUD installs its hotkey tap with `tailAppendEventTap`, so it sits *after* any other session-level event taps in the chain. If you use HyperCaps (or another tool that synthesises modifier flags), ShortcutHUD will see your transformed key events correctly. Tools that consume events fully — for example a hyper-key remap that converts caps-/ into a different shortcut entirely — will hide that input from ShortcutHUD by design.

## Building from Source

ShortcutHUD uses Swift Package Manager. No Xcode project is required.

```bash
cd ~/Desktop/"Jorvik Software"/ShortcutHUD
./build.sh
open _BuildOutput/ShortcutHUD.app
```

The build script runs `swift build -c release`, then assembles the `.app` bundle in `_BuildOutput/` with the executable, icon, and Info.plist.

To regenerate the app icon from `generate_icon.swift`:

```bash
swift generate_icon.swift
```

This rebuilds the `.iconset` and produces `Resources/AppIcon.icns`.

## How It Works (Technical)

1. **Global hotkey** — a `CGEventTap` at `cgSessionEventTap` / `tailAppendEventTap` listens for the configured `keyDown`. On match it posts a notification consumed by the main thread.
2. **Menu enumeration** — `AXUIElementCopyAttributeValue` walks the frontmost app's menu bar recursively, collecting `AXMenuItem` titles, key equivalents, modifier masks, and AX glyph codes. The walk runs on a background queue with a hard timeout to keep the HUD responsive.
3. **System shortcuts** — `CopySymbolicHotKeys` (HIToolbox) returns the macOS system shortcuts. The symbol is resolved via `dlsym` so a future macOS that strips it degrades gracefully.
4. **Activation** — for an app shortcut, the captured `AXUIElement` is invoked via `AXUIElementPerformAction(_, kAXPressAction)` against the menu item.

## Known Limitations (v1)

- **System shortcuts are list-only.** Activating a system shortcut from the HUD is not yet implemented; it dismisses the HUD without firing the action.
- **Third-party hyper-key tools** (Karabiner, Raycast, BetterTouchTool) do not appear in the HUD — there is no public macOS API exposing them.
- **Disabled menu items** are listed but greyed out; activating them does nothing.

## Troubleshooting

### The hotkey does nothing

Check the menu-bar icon. If it shows `⚠️`, Input Monitoring is missing — open Settings → Grant Access. If the icon is `⌘` and the hotkey still does nothing, another tool higher in the event-tap chain may be consuming the event before it reaches ShortcutHUD.

### The HUD opens but is empty

The captured app didn't expose its menus to the Accessibility API. Some Electron apps and games do this. There is no workaround at the OS level.

### The HUD appears on the wrong space or display

The HUD always opens on the active space and the screen containing the cursor. If the HUD has been dragged, resize/move state is restored on next open. To reset, delete the saved frame:

```bash
defaults delete cc.jorviksoftware.ShortcutHUD "NSWindow Frame ShortcutHUD.HUDPanel"
```

---

ShortcutHUD is provided by [Jorvik Software](https://jorviksoftware.cc/utilities/shortcuthud). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).

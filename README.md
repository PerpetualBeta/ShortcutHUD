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

When you press the hotkey the HUD opens an adaptive multi-column grid of every shortcut it can find for your current keyboard, grouped by source:

- **Frontmost app** — the captured app's menu structure (File, Edit, View, …) walked via the Accessibility API.
- **Per-app overrides** — any app's `NSUserKeyEquivalents` overrides (System Settings → Keyboard → App Shortcuts).
- **Hotkey utilities** — top-level `{keyCode, modifierFlags}` preference dicts as written by Rectangle, the `KeyboardShortcuts` Swift library, and similar window-management / hotkey tools.
- **macOS Services** — entries with a `key_equivalent` in `pbs.plist`.
- **Hammerspoon** — `hs.hotkey.bind(...)` calls in `~/.hammerspoon/*.lua`.
- **Keyboard Maestro** — HotKey-triggered macros in the macros plist.
- **macOS** — the system symbolic hotkeys (`CopySymbolicHotKeys`).

| Action | Key |
|--------|-----|
| Filter | type to fuzzy-match against title and path |
| Move selection | `↑` / `↓` |
| Activate selected | `↩` |
| Dismiss | `⎋` or click outside |

Activating an app shortcut invokes the corresponding menu item in the captured app. Sources where ShortcutHUD can only observe the binding (Rectangle, Hammerspoon, Services, …) are list-only — press the actual hotkey to fire them.

### What gets filtered out

- **Bindings owned by apps that aren't running.** Hammerspoon is dead, Rectangle quit — those entries don't appear, because the binding wouldn't fire anyway.
- **Bindings to keys not on any connected keyboard.** F13–F20 and the numeric keypad are dropped on a MacBook-only setup; plug a Magic Keyboard with Numeric Keypad in and they reappear automatically. Detection is by HID product name.

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
2. **Menu enumeration** — `AXUIElementCopyAttributeValue` walks the frontmost app's menu bar recursively, collecting `AXMenuItem` titles, key equivalents, modifier masks, and AX glyph codes.
3. **Per-app preferences sweep** — every plist in `~/Library/Preferences/` whose owning app is currently running is read for two patterns: `NSUserKeyEquivalents` dictionaries and top-level `{keyCode, modifierFlags}` entries.
4. **System sources** — `CopySymbolicHotKeys` (HIToolbox) for macOS shortcuts, `pbs.plist` `NSServicesStatus` for the Services menu, the `NSGlobalDomain` `NSUserKeyEquivalents` for global menu overrides.
5. **Tool-specific parsers** — `~/.hammerspoon/*.lua` is regex-scanned for `hs.hotkey.bind(...)` and modal `:bind(...)` calls; `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist` is walked for HotKey triggers. Both gated on the providing process being alive.
6. **Keyboard-capability filter** — `IOHIDManager` enumerates connected keyboards; their product names are matched against known Apple layouts (built-in MacBook, Magic Keyboard with/without Numeric Keypad). Shortcuts bound to keys not on any connected keyboard are dropped.
7. **Activation** — for an app shortcut, the captured `AXUIElement` is invoked via `AXUIElementPerformAction(_, kAXPressAction)`. Other sources are list-only.

All disk and AX work runs on a background queue with hard timeouts so a slow target can't hang the HUD opening.

## Known Limitations

- **Activation is app-menu-only.** Bindings discovered through preference sweeps, Hammerspoon, Keyboard Maestro, or `CopySymbolicHotKeys` are list-only — the HUD displays them but can't fire them. Press the actual hotkey to invoke.
- **Disabled menu items** are listed but greyed out; activating them does nothing.
- **Carbon hotkeys without a corresponding plist** don't appear unless the app stores its binding in one of the patterns above. Apps that register via `RegisterEventHotKey` purely in code, with no on-disk record, are invisible.
- **Hammerspoon Lua parser is a regex**, not a real interpreter. `hs.hotkey.bind` calls inside complex expressions, behind variables, or computed dynamically may be missed.
- **Third-party non-Apple keyboards** are assumed to have every key (so we don't over-filter). If your external 60% reports as "MyKeyboard" rather than a recognised Apple model, F13+ shortcuts will still appear even though you can't type them.

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

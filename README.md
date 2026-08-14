# ShortcutHUD

A macOS keyboard-shortcut HUD. Press a global hotkey and a panel slides in showing every keyboard shortcut available in the frontmost app, plus the macOS system shortcuts — searchable, multi-column, light/dark adaptive.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

Install it with [Homebrew](https://brew.sh):

```sh
brew install --cask perpetualbeta/jorvik/shortcuthud
```

Or download it from the [latest release](https://github.com/PerpetualBeta/ShortcutHUD/releases/latest). Then:

1. Double-click `ShortcutHUD.app` to launch it (or build from source — see below)
2. A `⌘` icon appears in your menu bar
3. Grant **Accessibility** and **Input Monitoring** permission when prompted

## Default Hotkey

`⌘⌥⌃⇧ /` (the hyper-key plus forward slash). Configurable in Settings.

## What You See

When you press the hotkey the HUD opens an adaptive multi-column grid of every shortcut it can find for your current keyboard, grouped into one outer pane per source:

- **Apple** — the macOS system menu (Force Quit, Lock Screen, Log Out, …) shared by every app.
- **Frontmost app** — the captured app's menu bar walked via the Accessibility API. Each top-level menu (File, Edit, View, …) is an inner section inside the app's pane.
- **Jorvik utilities** — every running Jorvik app publishes its registered global hotkeys via `JorvikHotkeyRegistry`; ShortcutHUD reads each one's bindings (BrowserCommander, Browser Notes, ScreenLock, WindowPin, ActiveSpace, …). Bindings tagged `.browser` are surfaced only when a web browser is frontmost.
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
- **Show icon in menu bar** — hide the menu-bar icon while ShortcutHUD keeps running (still reachable via its keyboard shortcut). Your choice persists across launches, including login auto-start. *Shown only on macOS 14–15 — on macOS 26 (Tahoe) and later, use System Settings → Menu Bar, which provides this natively.*
- **Menu bar icon pill** — optional grey background for stronger contrast on busy or wallpaper-tinted menu bars (off by default)
- **Launch at Login** — start automatically when you log in

If you've hidden the menu-bar icon and want it back, simply re-open ShortcutHUD from your Applications folder — it reappears immediately.

Auto-updates are handled by Sparkle. Use the **Check for Updates…** entry in the menu to check on demand; Sparkle's prompt offers an "Automatically download and install updates in the future" checkbox the first time an update is available.

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
gmake build
open .build/ShortcutHUD.app
```

Requires GNU Make 4.x — `brew install make` installs it as `gmake`. The target is defined in the shared `release.mk` from `jorvik-release/`.

To regenerate the app icon from `generate_icon.swift`:

```bash
swift generate_icon.swift
```

This rebuilds the `.iconset` and produces `Resources/AppIcon.icns`.

## How It Works (Technical)

1. **Global hotkey** — a `CGEventTap` at `cgSessionEventTap` / `tailAppendEventTap` listens for the configured `keyDown`. On match it posts a notification consumed by the main thread.
2. **Menu enumeration** — `AXUIElementCopyAttributeValue` walks the frontmost app's menu bar recursively, collecting `AXMenuItem` titles, key equivalents, modifier masks, and AX glyph codes. The Apple menu (always the first child of the menu bar) is split off into its own outer pane; everything else nests under a pane named after the captured app.
3. **Jorvik registry** — every other running Jorvik app is queried via `JorvikHotkeyRegistry.read(from:)`, which reads each app's published list of registered hotkeys (action title, keyCode, modifiers, active context). Entries marked `.browser` are filtered out unless the captured app's bundle ID is registered as an `http` handler — so BrowserCommander and Browser Notes only surface when a real web browser is frontmost.
4. **Per-app preferences sweep** — every plist in `~/Library/Preferences/` whose owning app is currently running is read for two patterns: `NSUserKeyEquivalents` dictionaries and top-level `{keyCode, modifierFlags}` entries.
5. **System sources** — `CopySymbolicHotKeys` (HIToolbox) for macOS shortcuts, `pbs.plist` `NSServicesStatus` for the Services menu, the `NSGlobalDomain` `NSUserKeyEquivalents` for global menu overrides.
6. **Tool-specific parsers** — `~/.hammerspoon/*.lua` is regex-scanned for `hs.hotkey.bind(...)` and modal `:bind(...)` calls; `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist` is walked for HotKey triggers. Both gated on the providing process being alive.
7. **Keyboard-capability filter** — `IOHIDManager` enumerates connected keyboards; their product names are matched against known Apple layouts (built-in MacBook, Magic Keyboard with/without Numeric Keypad). Shortcuts bound to keys not on any connected keyboard are dropped.
8. **Activation** — for an app shortcut, the captured `AXUIElement` is invoked via `AXUIElementPerformAction(_, kAXPressAction)`. Other sources are list-only.

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

ShortcutHUD is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).

import AppKit
import ApplicationServices
import CoreServices
import IOKit.hid

enum MenuEnumerator {

    private static let walkQueue = DispatchQueue(label: "cc.jorviksoftware.shortcuthud.menuwalk", qos: .userInitiated)

    /// Walk the foreground app's menu bar and collect every leaf shortcut, with a hard timeout.
    /// Runs the AX work on a dedicated queue so a slow target app can't hang the main thread.
    static func shortcuts(forPID pid: pid_t, timeout: TimeInterval = 0.5) -> [ShortcutItem] {
        let semaphore = DispatchSemaphore(value: 0)
        var collected: [ShortcutItem] = []

        walkQueue.async {
            let app = AXUIElementCreateApplication(pid)
            var menuBarRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
                  let menuBar = menuBarRef else {
                semaphore.signal(); return
            }
            // The menu bar's children are the top-level menus (App / File / Edit / …).
            // First child is usually the apple/app menu — skip its label, walk the rest normally.
            walk(menuBar as! AXUIElement, path: [], into: &collected, depth: 0)
            semaphore.signal()
        }

        let deadline = DispatchTime.now() + timeout
        _ = semaphore.wait(timeout: deadline)
        return collected
    }

    /// Scan every app preference plist for two well-known shortcut storage
    /// patterns and surface anything user-bound:
    ///
    /// 1. `NSUserKeyEquivalents` — the macOS-wide menu-key-override mechanism
    ///    used by System Settings → Keyboard → App Shortcuts. Each entry is
    ///    `"Menu Title" = "@~^$X"` (`@`=⌘, `$`=⇧, `~`=⌥, `^`=⌃, trailing char = key).
    /// 2. Top-level `{keyCode: Int, modifierFlags: Int}` dictionaries — the
    ///    pattern used by Rectangle, the KeyboardShortcuts library, and many
    ///    window-management / hotkey utilities. Modifiers are NSEvent layout.
    ///
    /// Both run on the AX walk queue with a hard timeout — disk I/O across
    /// hundreds of plists must not block the HUD opening.
    static func userKeyEquivalents(timeout: TimeInterval = 1.0) -> [ShortcutItem] {
        let semaphore = DispatchSemaphore(value: 0)
        var items: [ShortcutItem] = []

        walkQueue.async {
            let fm = FileManager.default
            let prefsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Preferences")
            guard let files = try? fm.contentsOfDirectory(atPath: prefsDir) else {
                semaphore.signal(); return
            }

            for file in files where file.hasSuffix(".plist") {
                let bundleID = String(file.dropLast(".plist".count))
                guard bundleID.contains(".") else { continue }
                // Skip apps that aren't running — their bindings aren't active.
                guard isAppRunning(bundleID: bundleID) else { continue }

                let path = (prefsDir as NSString).appendingPathComponent(file)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                else { continue }

                let appName = appDisplayName(forBundleID: bundleID) ?? bundleID

                // 1. NSUserKeyEquivalents
                if let nuke = plist["NSUserKeyEquivalents"] as? [String: String] {
                    for (menuTitle, encoded) in nuke {
                        guard let parsed = parseNSUserKeyEquivalent(encoded) else { continue }
                        items.append(ShortcutItem(
                            title: menuTitle,
                            path: [appName],
                            modifiers: Int(parsed.modifiers.rawValue),
                            cmdChar: parsed.key,
                            virtualKey: nil,
                            glyph: nil,
                            enabled: true,
                            source: .system,
                            axElement: nil
                        ))
                    }
                }

                // 2. Rectangle-style {keyCode, modifierFlags} entries
                for (key, value) in plist {
                    guard let dict = value as? [String: Any],
                          let kc = (dict["keyCode"] as? NSNumber)?.intValue,
                          let mf = (dict["modifierFlags"] as? NSNumber)?.intValue,
                          mf > 0,                           // skip unbound entries (modifiers cleared)
                          kc >= 0, kc < 256                 // skip 0xFFFF "no key" sentinels
                    else { continue }

                    items.append(ShortcutItem(
                        title: humaniseActionKey(key),
                        path: [appName],
                        modifiers: mf,
                        cmdChar: "",
                        virtualKey: kc,
                        glyph: nil,
                        enabled: true,
                        source: .system,
                        axElement: nil
                    ))
                }
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
        return items
    }

    /// Whether a given app bundle is currently a running process. Used to
    /// gate config-derived shortcut sources so dead configs (left-over
    /// Hammerspoon dotfile, uninstalled Rectangle, etc.) don't surface.
    private static func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    // MARK: - Jorvik registry

    /// Read the `JorvikHotkeyRegistry` from every running .accessory app.
    /// `.browser`-context entries are surfaced only when the captured app is a
    /// registered HTTP handler. Other Jorvik apps publish `.anywhere` entries
    /// which always show.
    static func jorvikRegisteredHotkeys(capturedBundleID: String?) -> [ShortcutItem] {
        let browserBundleIDs = httpHandlerBundleIDs()
        let isBrowser = capturedBundleID
            .map { browserBundleIDs.contains($0.lowercased()) } ?? false

        var items: [ShortcutItem] = []
        let myPID = getpid()
        for app in NSWorkspace.shared.runningApplications {
            // Skip ourselves: the user just pressed our hotkey to open the
            // HUD, so listing it back at them is noise.
            guard app.processIdentifier > 0, app.processIdentifier != myPID,
                  app.activationPolicy == .accessory,
                  let bundleID = app.bundleIdentifier else { continue }

            let hotkeys = JorvikHotkeyRegistry.read(from: bundleID)
            guard !hotkeys.isEmpty else { continue }

            let appName = app.localizedName ?? bundleID
            for hk in hotkeys {
                switch hk.activeContext {
                case .browser where !isBrowser: continue
                default: break
                }
                items.append(ShortcutItem(
                    title: hk.actionTitle,
                    path: [appName],
                    modifiers: Int(hk.modifiers),
                    cmdChar: "",
                    virtualKey: Int(hk.keyCode),
                    glyph: nil,
                    enabled: true,
                    source: .system,
                    axElement: nil
                ))
            }
        }
        return items
    }

    /// Bundle IDs of every app registered as an HTTP handler — Safari, Chrome,
    /// Edge, Firefox, Arc, Brave, Orion, etc. Used to decide "browser frontmost".
    private static func httpHandlerBundleIDs() -> Set<String> {
        guard let raw = LSCopyAllHandlersForURLScheme("http" as CFString)?.takeRetainedValue() as? [String] else {
            return []
        }
        return Set(raw.map { $0.lowercased() })
    }

    // MARK: - Keyboard capability gating

    /// Mac virtual key codes that aren't physically reachable on any connected
    /// keyboard, derived from each device's product name. Apple's HID
    /// descriptors advertise every standard keyboard usage regardless of which
    /// physical keys exist, so element-level inspection is useless — we have
    /// to recognise the keyboard model by name.
    static func unavailableKeyCodes() -> Set<Int> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 1,   // Generic Desktop
            kIOHIDDeviceUsageKey as String: 6,        // Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return []   // no keyboards detected — don't filter anything
        }

        // Union of capabilities across every connected keyboard.
        var maxFKey = 0
        var hasKeypad = false
        for device in devices {
            let raw = (IOHIDDeviceGetProperty(device, "Product" as CFString) as? String ?? "").lowercased()
            let caps = capabilities(forProductName: raw)
            maxFKey = max(maxFKey, caps.maxFKey)
            hasKeypad = hasKeypad || caps.hasKeypad
        }

        var unavailable: Set<Int> = []
        // Mac virtual key codes for F13–F20 (the F-keys missing on built-in
        // and basic Magic Keyboard layouts).
        let fkeyVKeys: [(fNum: Int, vkey: Int)] = [
            (13, 105), (14, 107), (15, 113), (16, 106),
            (17, 64),  (18, 79),  (19, 80),  (20, 90),
        ]
        for (n, v) in fkeyVKeys where n > maxFKey { unavailable.insert(v) }

        if !hasKeypad {
            // All keypad-cluster vkeys (numbers, operators, enter, clear).
            unavailable.formUnion([65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92])
        }
        return unavailable
    }

    private struct KeyboardCaps {
        let maxFKey: Int
        let hasKeypad: Bool
    }

    private static func capabilities(forProductName name: String) -> KeyboardCaps {
        // Built-in MacBook keyboard: F1–F12, no keypad.
        if name.contains("internal keyboard") {
            return KeyboardCaps(maxFKey: 12, hasKeypad: false)
        }
        // Magic Keyboard family: with-keypad variants add F13–F19 and a keypad.
        if name.contains("magic keyboard") {
            let withKeypad = name.contains("numeric keypad")
            return KeyboardCaps(maxFKey: withKeypad ? 19 : 12, hasKeypad: withKeypad)
        }
        // Anything else (third-party externals): assume a full keyboard so
        // we don't over-filter for keys that probably do exist.
        return KeyboardCaps(maxFKey: 24, hasKeypad: true)
    }

    private static func appDisplayName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return nil }
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? bundle.bundleURL.deletingPathExtension().lastPathComponent
    }

    private static func parseNSUserKeyEquivalent(_ s: String) -> (modifiers: NSEvent.ModifierFlags, key: String)? {
        var mods: NSEvent.ModifierFlags = []
        var keyPart = ""
        for ch in s {
            switch ch {
            case "@": mods.insert(.command)
            case "$": mods.insert(.shift)
            case "~": mods.insert(.option)
            case "^": mods.insert(.control)
            default:  keyPart.append(ch)
            }
        }
        let trimmed = keyPart.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return (mods, trimmed)
    }

    /// "leftHalf" → "Left Half"; "almostMaximize" → "Almost Maximize".
    private static func humaniseActionKey(_ key: String) -> String {
        var result = ""
        var prevWasLower = false
        for ch in key {
            if ch.isUppercase && prevWasLower { result.append(" ") }
            result.append(ch)
            prevWasLower = ch.isLowercase
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    // MARK: - Global NSUserKeyEquivalents

    /// `defaults read -g NSUserKeyEquivalents` — the "any application"
    /// fallback dictionary that applies to every app's menu items.
    static func globalUserKeyEquivalents() -> [ShortcutItem] {
        var items: [ShortcutItem] = []
        guard let raw = CFPreferencesCopyAppValue("NSUserKeyEquivalents" as CFString, kCFPreferencesAnyApplication),
              let dict = raw as? [String: String] else { return items }
        for (menuTitle, encoded) in dict {
            guard let parsed = parseNSUserKeyEquivalent(encoded) else { continue }
            items.append(ShortcutItem(
                title: menuTitle, path: ["Global"],
                modifiers: Int(parsed.modifiers.rawValue),
                cmdChar: parsed.key, virtualKey: nil, glyph: nil,
                enabled: true, source: .system, axElement: nil
            ))
        }
        return items
    }

    // MARK: - Services menu

    /// `~/Library/Preferences/pbs.plist` → `NSServicesStatus`. Each entry's
    /// key is `"<provider> - <UUID> - <action>"`; the value carries
    /// `key_equivalent` in NSUserKeyEquivalents string format.
    static func servicesShortcuts() -> [ShortcutItem] {
        var items: [ShortcutItem] = []
        guard let raw = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, "pbs" as CFString),
              let dict = raw as? [String: [String: Any]] else { return items }
        for (key, value) in dict {
            guard let encoded = value["key_equivalent"] as? String,
                  let parsed = parseNSUserKeyEquivalent(encoded) else { continue }
            // Key format: "<provider> - <UUID> - <action>". Use the action
            // segment as the title; if missing, fall back to the raw key.
            let parts = key.components(separatedBy: " - ")
            let title = parts.last.flatMap { humaniseActionKey($0) } ?? key
            items.append(ShortcutItem(
                title: title, path: ["macOS Services"],
                modifiers: Int(parsed.modifiers.rawValue),
                cmdChar: parsed.key, virtualKey: nil, glyph: nil,
                enabled: true, source: .system, axElement: nil
            ))
        }
        return items
    }

    // MARK: - Hammerspoon

    /// Parse `~/.hammerspoon/init.lua` (and any `*.lua` siblings) for
    /// `hs.hotkey.bind({mods}, "key", ...)` and `<modal>:bind('mods', 'key', ...)`.
    /// Skipped when Hammerspoon isn't running — leftover config files don't
    /// fire bindings and shouldn't pollute the HUD.
    static func hammerspoonShortcuts() -> [ShortcutItem] {
        var items: [ShortcutItem] = []
        guard isAppRunning(bundleID: "org.hammerspoon.Hammerspoon") else { return items }
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".hammerspoon")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return items }

        let bindArrayPattern = try? NSRegularExpression(
            pattern: #"hs\.hotkey\.bind\s*\(\s*\{([^}]*)\}\s*,\s*["']([^"']+)["']"#
        )
        let bindStringPattern = try? NSRegularExpression(
            pattern: #"\b(\w+):bind\s*\(\s*["']([^"']*)["']\s*,\s*["']([^"']+)["']"#
        )

        for case let path as String in enumerator where path.hasSuffix(".lua") {
            let full = (dir as NSString).appendingPathComponent(path)
            guard let source = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..., in: source)

            bindArrayPattern?.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let m = match,
                      let modsRange = Range(m.range(at: 1), in: source),
                      let keyRange = Range(m.range(at: 2), in: source) else { return }
                let mods = parseLuaModList(String(source[modsRange]))
                let key = String(source[keyRange])
                items.append(ShortcutItem(
                    title: "Bind \(key.uppercased())",
                    path: ["Hammerspoon"],
                    modifiers: Int(mods.rawValue),
                    cmdChar: key, virtualKey: nil, glyph: nil,
                    enabled: true, source: .system, axElement: nil
                ))
            }

            bindStringPattern?.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let m = match,
                      let nameRange = Range(m.range(at: 1), in: source),
                      let modsRange = Range(m.range(at: 2), in: source),
                      let keyRange = Range(m.range(at: 3), in: source) else { return }
                let modal = String(source[nameRange])
                // Skip the array-form match accidentally re-captured via varname:bind
                if modal == "hs" { return }
                let mods = parseLuaModList(String(source[modsRange]))
                let key = String(source[keyRange])
                items.append(ShortcutItem(
                    title: "\(modal) → \(key.uppercased())",
                    path: ["Hammerspoon"],
                    modifiers: Int(mods.rawValue),
                    cmdChar: key, virtualKey: nil, glyph: nil,
                    enabled: true, source: .system, axElement: nil
                ))
            }
        }
        return items
    }

    private static func parseLuaModList(_ s: String) -> NSEvent.ModifierFlags {
        var mods: NSEvent.ModifierFlags = []
        let tokens = s.split(whereSeparator: { ", \"'".contains($0) }).map { String($0).lowercased() }
        for t in tokens {
            switch t {
            case "cmd", "command": mods.insert(.command)
            case "alt", "option": mods.insert(.option)
            case "ctrl", "control": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: break
            }
        }
        return mods
    }

    // MARK: - Keyboard Maestro

    /// Walk the macros plist for HotKey triggers (KeyCode + Modifiers fields
    /// inside a `Triggers` array). The macro `Name` is the title. Gated on the
    /// KM Engine process being alive — only the engine fires the triggers.
    static func keyboardMaestroShortcuts() -> [ShortcutItem] {
        var items: [ShortcutItem] = []
        guard isAppRunning(bundleID: "com.stairways.keyboardmaestro.engine") else { return items }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(
            "Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist"
        )
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let groups = plist["MacroGroups"] as? [[String: Any]] else { return items }

        for group in groups {
            guard let macros = group["Macros"] as? [[String: Any]] else { continue }
            for macro in macros {
                guard let name = macro["Name"] as? String,
                      let triggers = macro["Triggers"] as? [[String: Any]] else { continue }
                for trigger in triggers {
                    // KM stores HotKey triggers with these field names. Some
                    // older files use lowercase keys — handle both.
                    let kc = (trigger["KeyCode"] ?? trigger["keyCode"]) as? NSNumber
                    let mf = (trigger["Modifiers"] ?? trigger["modifierFlags"]) as? NSNumber
                    guard let kcVal = kc?.intValue, let mfVal = mf?.intValue,
                          mfVal > 0, kcVal >= 0, kcVal < 256 else { continue }
                    items.append(ShortcutItem(
                        title: name, path: ["Keyboard Maestro"],
                        modifiers: mfVal, cmdChar: "",
                        virtualKey: kcVal, glyph: nil,
                        enabled: true, source: .system, axElement: nil
                    ))
                }
            }
        }
        return items
    }

    private static func walk(_ element: AXUIElement, path: [String], into out: inout [ShortcutItem], depth: Int) {
        // Defensive depth guard — real menus rarely exceed 6.
        if depth > 12 { return }

        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return }

        for (idx, child) in children.enumerated() {
            // The Apple menu is always the first child of the menu bar. Force
            // its path label to "Apple" — some apps leave the title empty
            // (system default), Electron apps explicitly title it "Apple".
            // The forced label gives `AppDelegate.showHUD` a stable signal to
            // promote it into its own top-level pane rather than nesting it
            // under the captured app.
            let rawTitle = copyString(child, kAXTitleAttribute) ?? ""
            let title = (depth == 0 && idx == 0) ? "Apple" : rawTitle
            let enabled = copyBool(child, kAXEnabledAttribute) ?? true

            let cmdChar    = copyString(child, kAXMenuItemCmdCharAttribute) ?? ""
            let modifiers  = copyInt(child, kAXMenuItemCmdModifiersAttribute) ?? 0
            let virtualKey = copyInt(child, kAXMenuItemCmdVirtualKeyAttribute)
            let glyph      = copyInt(child, kAXMenuItemCmdGlyphAttribute)

            // A shortcut is present if any of glyph / virtualKey / cmdChar is populated.
            // cmdChar alone misses function keys, arrows, return, escape, etc.
            let hasShortcut = !cmdChar.isEmpty
                || (virtualKey != nil)
                || (glyph != nil && glyph != 0)

            if hasShortcut && !title.isEmpty {
                out.append(ShortcutItem(
                    title: title, path: path,
                    modifiers: modifiers,
                    cmdChar: cmdChar,
                    virtualKey: virtualKey,
                    glyph: glyph,
                    enabled: enabled,
                    source: .app,
                    axElement: child
                ))
            }

            // Recurse — submenus appear as child of the menu item.
            // The path for submenus uses the title of the parent menu item.
            let nextPath = path.isEmpty ? [title] : (title.isEmpty ? path : path + [title])
            walk(child, path: nextPath, into: &out, depth: depth + 1)
        }
    }

    /// Activate a menu item via AX. Reads the owning PID directly from the AX
    /// element so the right app is activated regardless of which one was
    /// frontmost when the HUD opened — important for menu-bar app shortcuts,
    /// where the action lives in the status-item owner, not the captured app.
    static func activate(_ item: ShortcutItem) {
        guard let element = item.axElement else { return }
        var ownerPID: pid_t = 0
        AXUIElementGetPid(element, &ownerPID)
        if ownerPID > 0, let runningApp = NSRunningApplication(processIdentifier: ownerPID) {
            runningApp.activate(options: [])
        }
        // Tiny delay so activation lands before the press — empirically reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    // MARK: - AX read helpers

    private static func copyString(_ element: AXUIElement, _ attr: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    private static func copyInt(_ element: AXUIElement, _ attr: String) -> Int? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success else { return nil }
        if let n = raw as? Int { return n }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }

    private static func copyBool(_ element: AXUIElement, _ attr: String) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &raw) == .success else { return nil }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }
}

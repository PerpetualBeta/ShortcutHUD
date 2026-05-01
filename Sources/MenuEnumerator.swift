import AppKit
import ApplicationServices

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

    private static func walk(_ element: AXUIElement, path: [String], into out: inout [ShortcutItem], depth: Int) {
        // Defensive depth guard — real menus rarely exceed 6.
        if depth > 12 { return }

        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return }

        for child in children {
            let title = copyString(child, kAXTitleAttribute) ?? ""
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

    /// Activate a menu item via AX. Activates the target app first so focus-dependent
    /// items like Paste work correctly — AX press alone fires the action without
    /// bringing the app forward.
    static func activate(_ item: ShortcutItem, targetPID: pid_t) {
        guard let element = item.axElement else { return }
        if let runningApp = NSRunningApplication(processIdentifier: targetPID) {
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

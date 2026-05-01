import AppKit

/// Reads the macOS system shortcuts (System Settings → Keyboard → Shortcuts) via
/// the HIToolbox SPI `CopySymbolicHotKeys`. Resolved through dlsym so a future
/// macOS that strips the symbol degrades gracefully to "app shortcuts only".
enum SymbolicHotkeys {

    // Real C signature: OSStatus CopySymbolicHotKeys(CFArrayRef *outArray).
    // Out-pointer + status return — not a value-returning function. Modeling
    // it incorrectly causes the function to write through whatever's in x0,
    // crashing inside HIToolbox with a __TEXT write fault.
    private typealias CopyFn = @convention(c) (UnsafeMutablePointer<Unmanaged<CFArray>?>) -> OSStatus

    static func all() -> [ShortcutItem] {
        guard let handle = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_LAZY) else { return [] }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "CopySymbolicHotKeys") else { return [] }
        let fn = unsafeBitCast(sym, to: CopyFn.self)
        var arrayRef: Unmanaged<CFArray>?
        let status = fn(&arrayRef)
        guard status == noErr, let unmanaged = arrayRef else { return [] }
        let cfArray = unmanaged.takeRetainedValue()
        guard let entries = cfArray as? [[String: Any]] else { return [] }

        var out: [ShortcutItem] = []
        for entry in entries {
            guard let id = entry["symbolichotkey.id"] as? Int,
                  let enabled = entry["symbolichotkey.enabled"] as? Bool,
                  enabled else { continue }
            guard let value = entry["symbolichotkey.value"] as? [String: Any] else {
                // Some entries use flat keys; try those.
                if let keyCode = entry["keyCode"] as? Int,
                   let mods = entry["modifiers"] as? Int {
                    out.append(makeItem(id: id, keyCode: keyCode, modifiers: mods))
                }
                continue
            }
            guard let params = value["parameters"] as? [Int], params.count >= 3 else { continue }
            // params[0] = printable char or 0xFFFF, params[1] = virtual key code, params[2] = modifiers (NSEvent flags)
            let keyCode = params[1]
            let modifiers = params[2]
            if keyCode < 0 { continue }
            out.append(makeItem(id: id, keyCode: keyCode, modifiers: modifiers))
        }
        // Sort by friendly title so the macOS section is stable.
        return out.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    private static func makeItem(id: Int, keyCode: Int, modifiers: Int) -> ShortcutItem {
        let title = nameMap[id] ?? "System shortcut #\(id)"
        return ShortcutItem(
            title: title,
            path: ["macOS"],
            modifiers: modifiers,
            cmdChar: "",
            virtualKey: keyCode,
            glyph: nil,
            enabled: true,
            source: .system,
            axElement: nil
        )
    }

    /// Subset of kSHK* IDs from <Carbon/HIToolbox/Events.h> with confidently-correct
    /// labels. Anything not in this map shows as "System shortcut #N" — honest is
    /// better than wrong.
    private static let nameMap: [Int: String] = [
        7:   "Move focus to the menu bar",
        8:   "Move focus to the Dock",
        9:   "Move focus to the active window",
        10:  "Move focus to the window toolbar",
        11:  "Move focus to the floating window",
        13:  "Move focus to status menus",
        14:  "Turn keyboard access on or off",
        15:  "Change the way Tab moves focus",
        27:  "Save picture of screen as a file",
        28:  "Copy picture of screen to the clipboard",
        29:  "Save picture of selected area as a file",
        30:  "Copy picture of selected area to the clipboard",
        32:  "Mission Control",
        33:  "Application windows",
        36:  "Show Desktop",
        59:  "Start dictation",
        60:  "Switch to previous input source",
        61:  "Switch to next input source",
        62:  "Show next tab",
        63:  "Show previous tab",
        64:  "Show Spotlight search",
        65:  "Show Finder search window",
        79:  "Move left a space",
        81:  "Move right a space",
        118: "Switch to Desktop 1",
        119: "Switch to Desktop 2",
        120: "Switch to Desktop 3",
        121: "Switch to Desktop 4",
        122: "Switch to Desktop 5",
        123: "Switch to Desktop 6",
        124: "Switch to Desktop 7",
        125: "Switch to Desktop 8",
        126: "Switch to Desktop 9",
        127: "Switch to Desktop 10",
        128: "Switch to Desktop 11",
        129: "Switch to Desktop 12",
        159: "Show Notification Center",
        160: "Show Launchpad",
        162: "Quick Note",
        184: "Screenshot and recording options",
    ]
}

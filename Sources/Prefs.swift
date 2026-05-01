import AppKit

enum Prefs {
    private static let keyCodeKey = "shortcutHUDKeyCode"
    private static let modifiersKey = "shortcutHUDModifiers"

    /// Default: ⌘⇧/ — same combo macOS uses for the Help menu's "Search" field.
    static let defaultKeyCode: UInt16 = 44   // /
    static let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    static func loadKeyCode() -> UInt16 {
        let v = UserDefaults.standard.object(forKey: keyCodeKey)
        if v == nil { return defaultKeyCode }
        return UInt16(UserDefaults.standard.integer(forKey: keyCodeKey))
    }

    static func loadModifiers() -> NSEvent.ModifierFlags {
        if let raw = UserDefaults.standard.object(forKey: modifiersKey) as? UInt {
            return NSEvent.ModifierFlags(rawValue: raw)
        }
        return defaultModifiers
    }

    static func save(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(modifiers.rawValue, forKey: modifiersKey)
    }
}

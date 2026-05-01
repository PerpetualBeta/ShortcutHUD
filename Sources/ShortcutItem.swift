import AppKit
import ApplicationServices

enum ShortcutSource {
    case app
    case system
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let title: String
    let path: [String]            // ["File"] or ["File", "Open Recent"]
    let modifiers: Int            // AX modifier flags (different bit layout from NSEvent — see ShortcutFormatter)
    let cmdChar: String
    let virtualKey: Int?
    let glyph: Int?
    let enabled: Bool
    let source: ShortcutSource
    let axElement: AXUIElement?   // nil for system entries

    var groupTitle: String { path.first ?? "" }
    var fullTitle: String {
        if path.count <= 1 { return title }
        return path.dropFirst().joined(separator: " \u{203A} ") + " \u{203A} " + title
    }
    var searchHaystack: String {
        (path + [title]).joined(separator: " ").lowercased()
    }
}

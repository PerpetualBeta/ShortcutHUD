import AppKit
import ApplicationServices

enum ShortcutSource {
    case app
    case system
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let title: String
    /// Where this shortcut sits in the HUD hierarchy.
    /// `path[0]` is the outer pane (app or source name).
    /// `path[1]` (if present) is the inner section (a menu name like "File"
    /// for captured-app items). Anything beyond is a submenu trail and shows
    /// in the row text via `fullTitle`.
    let path: [String]
    let modifiers: Int            // AX modifier flags (different bit layout from NSEvent — see ShortcutFormatter)
    let cmdChar: String
    let virtualKey: Int?
    let glyph: Int?
    let enabled: Bool
    let source: ShortcutSource
    let axElement: AXUIElement?   // nil for system entries

    var paneTitle: String { path.first ?? "" }
    var sectionTitle: String? { path.count >= 2 ? path[1] : nil }

    /// The text shown in a row. Strips the pane and section prefixes so the
    /// surrounding visual hierarchy isn't echoed in the row text.
    var fullTitle: String {
        if path.count <= 2 { return title }
        return path.dropFirst(2).joined(separator: " \u{203A} ") + " \u{203A} " + title
    }
    var searchHaystack: String {
        (path + [title]).joined(separator: " ").lowercased()
    }

    /// Returns a copy with `prefix` prepended to `path`. Used to wrap the
    /// captured app's menu items inside a pane named after the app.
    func prepending(_ prefix: String) -> ShortcutItem {
        ShortcutItem(
            title: title,
            path: [prefix] + path,
            modifiers: modifiers,
            cmdChar: cmdChar,
            virtualKey: virtualKey,
            glyph: glyph,
            enabled: enabled,
            source: source,
            axElement: axElement
        )
    }
}

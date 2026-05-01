import AppKit
import Carbon.HIToolbox

// AX kAXMenuItemCmdModifiersAttribute uses a bitmask with a different layout
// than NSEvent.ModifierFlags. The bits are:
//   bit 0 (1)  = ⇧ Shift
//   bit 1 (2)  = ⌥ Option
//   bit 2 (4)  = ⌃ Control
//   bit 3 (8)  = command absent (i.e. ⌘ is *not* held — "no command" flag)
// So a normal ⌘-only shortcut reports modifiers == 0.
private struct AXMods {
    static let shift   = 1
    static let option  = 2
    static let control = 4
    static let noCmd   = 8
}

enum ShortcutFormatter {

    /// Format an app-menu shortcut, preferring glyph → virtualKey → cmdChar.
    static func appMenu(modifiers: Int, cmdChar: String, virtualKey: Int?, glyph: Int?) -> String {
        var parts: [String] = []
        if (modifiers & AXMods.control) != 0 { parts.append("⌃") }
        if (modifiers & AXMods.option)  != 0 { parts.append("⌥") }
        if (modifiers & AXMods.shift)   != 0 { parts.append("⇧") }
        if (modifiers & AXMods.noCmd)   == 0 { parts.append("⌘") }

        if let g = glyph, g != 0, let s = glyphString(g) { parts.append(s); return parts.joined() }
        if let v = virtualKey, let s = virtualKeyString(UInt16(v)) { parts.append(s); return parts.joined() }
        if !cmdChar.isEmpty { parts.append(cmdChar.uppercased()); return parts.joined() }
        return parts.joined()
    }

    /// Format a system symbolic-hotkey shortcut (keyCode + modifiers in CG layout).
    static func system(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        // CGEventFlags layout (matches NSEvent.ModifierFlags raw bits in the high half).
        // The symbolichotkey plist uses NSEvent.ModifierFlags raw values.
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if let s = virtualKeyString(UInt16(keyCode)) { parts.append(s) }
        return parts.joined()
    }

    // Carbon glyph code → display string (subset that actually appears in menus).
    private static func glyphString(_ glyph: Int) -> String? {
        switch glyph {
        case 0x02: return "⇥"   // kMenuTabRightGlyph
        case 0x03: return "⇤"   // kMenuTabLeftGlyph
        case 0x04: return "↩"   // kMenuReturnGlyph
        case 0x05: return "↩"   // kMenuReturnR2LGlyph
        case 0x09: return "⌫"   // kMenuDeleteLeftGlyph
        case 0x0A: return "⌦"   // kMenuDeleteRightGlyph
        case 0x0B: return "⌤"   // kMenuEnterGlyph
        case 0x18: return "⇧"   // kMenuShiftGlyph (rarely seen)
        case 0x19: return "⌃"   // kMenuControlGlyph
        case 0x1A: return "⌥"   // kMenuOptionGlyph
        case 0x1B: return "⎋"   // kMenuEscapeGlyph
        case 0x61: return "F1";  case 0x62: return "F2"
        case 0x63: return "F3";  case 0x64: return "F4"
        case 0x65: return "F5";  case 0x66: return "F6"
        case 0x67: return "F7";  case 0x68: return "F8"
        case 0x69: return "F9";  case 0x6A: return "F10"
        case 0x6B: return "F11"; case 0x6C: return "F12"
        case 0x6D: return "F13"; case 0x6E: return "F14"; case 0x6F: return "F15"
        case 0x70: return "←";   case 0x71: return "→"
        case 0x72: return "↓";   case 0x73: return "↑"
        case 0x77: return "␣"   // kMenuSpaceGlyph
        case 0x80: return "⌫"   // kMenuClearGlyph
        case 0x82: return "⇞"   // page up
        case 0x83: return "⇟"   // page down
        case 0x84: return "↖"   // home
        case 0x85: return "↘"   // end
        default: return nil
        }
    }

    private static func virtualKeyString(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "A";   case 1: return "S";   case 2: return "D";   case 3: return "F"
        case 4: return "H";   case 5: return "G";   case 6: return "Z";   case 7: return "X"
        case 8: return "C";   case 9: return "V";   case 11: return "B";  case 12: return "Q"
        case 13: return "W";  case 14: return "E";  case 15: return "R";  case 16: return "Y"
        case 17: return "T"
        case 18: return "1";  case 19: return "2";  case 20: return "3";  case 21: return "4"
        case 22: return "6";  case 23: return "5";  case 24: return "="
        case 25: return "9";  case 26: return "7";  case 27: return "-"
        case 28: return "8";  case 29: return "0"
        case 30: return "]";  case 31: return "O";  case 32: return "U";  case 33: return "["
        case 34: return "I";  case 35: return "P";  case 36: return "↩"
        case 37: return "L";  case 38: return "J";  case 39: return "'"
        case 40: return "K";  case 41: return ";";  case 42: return "\\"
        case 43: return ",";  case 44: return "/";  case 45: return "N"
        case 46: return "M";  case 47: return "."
        case 48: return "⇥";  case 49: return "␣"
        case 50: return "`";  case 51: return "⌫";  case 53: return "⎋"
        case 71: return "⌧"   // keypad clear
        case 76: return "⌤"   // keypad enter
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 99: return "F3"
        case 100: return "F8"; case 101: return "F9"; case 103: return "F11"
        case 105: return "F13"; case 107: return "F14"; case 109: return "F10"
        case 111: return "F12"; case 113: return "F15"
        case 115: return "↖"; case 116: return "⇞"; case 117: return "⌦"; case 119: return "↘"
        case 121: return "⇟"
        case 118: return "F4"; case 120: return "F2"; case 122: return "F1"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        default: return nil
        }
    }
}

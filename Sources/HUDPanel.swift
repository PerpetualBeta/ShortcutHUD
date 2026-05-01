import AppKit
import SwiftUI

@MainActor
protocol HUDDelegate: AnyObject {
    func hudMoveSelectionUp()
    func hudMoveSelectionDown()
    func hudActivateSelected()
    func hudDismiss()
}

/// NSPanel subclass that becomes key without activating the app.
/// Pattern B from the Jorvik convention `accessory-popover-focus`.
final class HUDPanel: NSPanel {
    weak var hudDelegate: HUDDelegate?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Let the search NSTextField handle its own keys (typing, backspace, etc.)
        if firstResponder is NSTextView {
            // ↑ ↓ Enter Esc still need to drive selection / activation / dismissal
            // even when the search field has focus.
            switch event.keyCode {
            case 126: hudDelegate?.hudMoveSelectionUp(); return
            case 125: hudDelegate?.hudMoveSelectionDown(); return
            case 36:  hudDelegate?.hudActivateSelected(); return
            case 53:  hudDelegate?.hudDismiss(); return
            default:  super.keyDown(with: event); return
            }
        }
        switch event.keyCode {
        case 126: hudDelegate?.hudMoveSelectionUp()
        case 125: hudDelegate?.hudMoveSelectionDown()
        case 36:  hudDelegate?.hudActivateSelected()
        case 53:  hudDelegate?.hudDismiss()
        default:  super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        hudDelegate?.hudDismiss()
    }
}

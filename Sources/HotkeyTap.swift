import AppKit
import ApplicationServices
import IOKit.hid
import os

private let hotkeyLog = Logger(subsystem: "cc.jorviksoftware.ShortcutHUD", category: "hotkey")

private var _eventTap: CFMachPort?
private var _keyCode: UInt16 = 0
private var _modifiers: CGEventFlags = []

private let _modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

extension Notification.Name {
    static let shortcutHUDHotkey = Notification.Name("ShortcutHUDHotkey")
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.intersection(_modifierMask)

    if _keyCode != 0 && keyCode == _keyCode && flags == _modifiers {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .shortcutHUDHotkey, object: nil)
        }
        return nil
    }
    return Unmanaged.passUnretained(event)
}

enum HotkeyTap {

    static var current: CFMachPort? { _eventTap }

    /// Whether Input Monitoring is currently granted, without prompting.
    static var accessGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system prompt for Input Monitoring on first call; on subsequent
    /// calls returns the cached state without prompting. Blocks until the user
    /// responds, so callers should dispatch off the main thread.
    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func setShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        _keyCode = keyCode
        _modifiers = modifiers.cgEventFlags
    }

    @discardableResult
    static func install() -> Bool {
        guard _eventTap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        // Tail-append (not head-insert): we're a passive detector, not a
        // transformer. Other taps that rewrite events upstream — notably
        // HyperCaps, which adds hyper-modifier flags on keyDown when its F18
        // marker is held — must run before us so we see the final flags. If
        // we head-insert, we sit ahead of HyperCaps and see the raw key event
        // without the synthesized modifiers, so the hotkey never matches.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: nil
        ) else {
            hotkeyLog.error("CGEvent.tapCreate returned nil — Input Monitoring permission likely missing")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _eventTap = tap
        return true
    }
}

extension NSEvent.ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.command) { result.insert(.maskCommand) }
        if contains(.control) { result.insert(.maskControl) }
        if contains(.option)  { result.insert(.maskAlternate) }
        if contains(.shift)   { result.insert(.maskShift) }
        return result
    }
}

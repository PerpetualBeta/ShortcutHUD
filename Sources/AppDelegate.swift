import AppKit
import ApplicationServices
import SwiftUI
import Sparkle

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, HUDDelegate {

    private var statusItem: NSStatusItem!
    private var hudPanel: HUDPanel?
    private var hudHostingController: NSHostingController<HUDView>?
    private let hudState = HUDState()
    private var clickOutsideMonitor: Any?

    /// Strong references to the AX-bearing items for the lifetime of the visible HUD.
    /// SwiftUI state alone is not enough — view recycling can drop the AXUIElements.
    private var liveItems: [ShortcutItem] = []
    private var capturedPID: pid_t = 0

    // @ObservationIgnored — @Observable's macro can't transform `lazy`.
    @ObservationIgnored let sparkleUserDriverDelegate = ShortcutHUDUserDriverDelegate()
    @ObservationIgnored lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: sparkleUserDriverDelegate
    )

    var activationKeyCode: UInt16 = Prefs.loadKeyCode() {
        didSet {
            HotkeyTap.setShortcut(keyCode: activationKeyCode, modifiers: activationModifiers)
            republishHotkey()
        }
    }
    var activationModifiers: NSEvent.ModifierFlags = Prefs.loadModifiers() {
        didSet {
            HotkeyTap.setShortcut(keyCode: activationKeyCode, modifiers: activationModifiers)
            republishHotkey()
        }
    }

    func activationDisplayString() -> String {
        guard activationKeyCode != 0 else { return "Not set" }
        return JorvikShortcutPanel.displayString(keyCode: activationKeyCode, modifiers: activationModifiers)
    }

    func persistShortcut() {
        Prefs.save(keyCode: activationKeyCode, modifiers: activationModifiers)
    }

    private func republishHotkey() {
        JorvikHotkeyRegistry.publish([
            JorvikHotkey(actionTitle: "Open ShortcutHUD",
                         keyCode: activationKeyCode,
                         modifiers: activationModifiers,
                         activeContext: .anywhere),
        ])
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPillColorKey()

        NSApp.setActivationPolicy(.accessory)

        // Prompt for AX permission on first launch — both menu enumeration and the
        // CGEvent tap require it.
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Configure tap with current shortcut and try to install it. Input
        // Monitoring is a separate TCC permission from Accessibility — without
        // it CGEventTap silently fails. requestAccess blocks until the user
        // responds, so dispatch it off-main; the install retries when the app
        // becomes active again (handler below).
        HotkeyTap.setShortcut(keyCode: activationKeyCode, modifiers: activationModifiers)
        republishHotkey()
        if !HotkeyTap.accessGranted {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = HotkeyTap.requestAccess()
            }
        }
        _ = HotkeyTap.install()
        updateHotkeyState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHotkey),
            name: .shortcutHUDHotkey, object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )

        // Redraw the status icon when the display configuration changes — the
        // menu bar's effective thickness can shrink (e.g. moving from a notched
        // display to an external one) and leave the pre-rendered pill cropped.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateHotkeyState()
        }

        _ = sparkleUpdater  // forces lazy init so Sparkle starts at launch
    }

    // One-shot removal of the user-chosen pill colour key from the old design.
    // The new pill uses fixed grey/light colours; the key is dead weight.
    private func migrateLegacyPillColorKey() {
        let migrated = "didMigratePillColorV2"
        if UserDefaults.standard.bool(forKey: migrated) { return }
        UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
        UserDefaults.standard.set(true, forKey: migrated)
    }

    /// Switches the menu-bar icon to a warning glyph when the global hotkey tap
    /// isn't installed. The user reaches Settings via the existing menu either way.
    func updateHotkeyState() {
        guard let button = statusItem?.button else { return }
        let installed = HotkeyTap.current != nil
        let symbolName = installed ? "command.square" : "exclamationmark.triangle.fill"
        let description = installed ? "ShortcutHUD" : "ShortcutHUD — Input Monitoring required"
        button.image = JorvikMenuBarPill.icon(
            symbolName: symbolName,
            tint: installed ? nil : .systemOrange,
            accessibilityDescription: description
        )
        button.toolTip = installed ? nil : "Input Monitoring required — open Settings to grant access"
    }

    @objc private func appBecameActive() {
        if HotkeyTap.current == nil { _ = HotkeyTap.install() }
        updateHotkeyState()
    }

    // MARK: - Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let actions: [JorvikMenuBuilder.ActionItem] = [
            .init(title: "Check for Updates\u{2026}", action: #selector(checkForUpdates(_:)), target: self)
        ]
        let built = JorvikMenuBuilder.buildMenu(
            appName: "ShortcutHUD",
            aboutAction: #selector(openAbout),
            settingsAction: #selector(openSettings),
            target: self,
            actions: actions
        )
        menu.removeAllItems()
        for item in built.items { built.removeItem(item); menu.addItem(item) }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        sparkleUpdater.checkForUpdates(sender)
    }

    @objc private func openAbout() {
        JorvikAboutView.showWindow(
            appName: "ShortcutHUD",
            repoName: "ShortcutHUD",
            productPage: "utilities/shortcuthud"
        )
    }

    @objc private func openSettings() {
        let delegate = self
        JorvikSettingsView.showWindow(appName: "ShortcutHUD") {
            ShortcutHUDSettingsContent(delegate: delegate)
        }
    }

    // MARK: - Hotkey

    @objc private func handleHotkey() {
        if hudPanel?.isVisible == true {
            dismissHUD()
            return
        }
        showHUD()
    }

    // MARK: - HUD lifecycle

    private func showHUD() {
        // Capture frontmost BEFORE we touch any window state.
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        capturedPID = front.processIdentifier

        // Walk every shortcut source we know how to read: the captured app's
        // menus, per-app NSUserKeyEquivalents + Rectangle-style preference
        // dicts, the global keyboard equivalents, the Services menu, the
        // user's Hammerspoon Lua bindings, Keyboard Maestro hotkey triggers,
        // and the macOS system symbolic hotkeys. AX and disk I/O run on
        // background queues with hard timeouts.
        var combined: [ShortcutItem] = []
        // Wrap the captured app's menu items in a pane named after the app, so
        // File/Edit/View become inner sections of "Microsoft Edge" (or whatever
        // is frontmost) rather than peers of Rectangle / ScreenLock / etc.
        // The Apple menu is system-owned and stays its own top-level pane —
        // the walker tags those items with path[0] == "Apple", so we leave
        // them alone instead of nesting under the captured app.
        let capturedPaneName = front.localizedName ?? "App"
        combined.append(contentsOf: MenuEnumerator.shortcuts(forPID: capturedPID).map { item in
            item.paneTitle == "Apple" ? item : item.prepending(capturedPaneName)
        })
        combined.append(contentsOf: MenuEnumerator.jorvikRegisteredHotkeys(capturedBundleID: front.bundleIdentifier))
        combined.append(contentsOf: MenuEnumerator.userKeyEquivalents())
        combined.append(contentsOf: MenuEnumerator.globalUserKeyEquivalents())
        combined.append(contentsOf: MenuEnumerator.servicesShortcuts())
        combined.append(contentsOf: MenuEnumerator.hammerspoonShortcuts())
        combined.append(contentsOf: MenuEnumerator.keyboardMaestroShortcuts())
        combined.append(contentsOf: SymbolicHotkeys.all())

        // Filter out shortcuts bound to keys that aren't on any connected
        // keyboard — they can't be triggered, so listing them only confuses.
        let unavailable = MenuEnumerator.unavailableKeyCodes()
        if !unavailable.isEmpty {
            combined.removeAll { item in
                guard let v = item.virtualKey else { return false }
                return unavailable.contains(v)
            }
        }

        liveItems = combined
        hudState.items = combined
        hudState.query = ""
        hudState.clampSelection()

        if hudPanel == nil { createPanel() }
        positionPanel()
        hudPanel?.makeKeyAndOrderFront(nil)
        // System shadow defaults to the rectangular window frame; force a
        // recompute from the rounded-corner alpha mask so the shadow follows
        // the actual visible shape. Deferred so the layer has rendered first.
        DispatchQueue.main.async { [weak self] in
            self?.hudPanel?.invalidateShadow()
        }

        // Outside-click dismissal — the panel is .nonactivatingPanel so the
        // captured app keeps frontmost status; we still want clicks elsewhere
        // to dismiss us.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.dismissHUD() }
        }
    }

    func dismissHUD() {
        hudPanel?.orderOut(nil)
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        liveItems.removeAll()
    }

    private func createPanel() {
        // Borderless + resizable. No `.titled` (it reserved invisible pixels
        // that cropped the footer) and no `.fullSizeContentView` (only relevant
        // with a title bar). HUDPanel.canBecomeKey lets us still receive keys.
        let p = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        p.minSize = NSSize(width: 520, height: 400)
        p.setFrameAutosaveName("ShortcutHUD.HUDPanel")
        p.isFloatingPanel = true
        p.level = .floating
        // Appear on whichever space the user is on when the hotkey fires, and
        // overlay full-screen apps. Without this, the panel stays on the space
        // it was first created on.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Borderless: drag anywhere on the visual-effect background to move the
        // panel. Rows have their own tap gestures so they aren't drag handles.
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.hudDelegate = self

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 880, height: 680))
        bg.autoresizingMask = [.width, .height]
        bg.material = .underWindowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        // CALayer cornerRadius alone doesn't propagate to the window's alpha
        // mask, so the system shadow draws as a rectangle around the rounded
        // visible shape. NSVisualEffectView.maskImage *does* propagate, and
        // AppKit uses it to compute the shadow shape correctly.
        let r: CGFloat = 12
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        bg.maskImage = mask

        let host = NSHostingController(rootView: HUDView(state: hudState) { [weak self] item in
            self?.activate(item)
        })
        host.view.frame = bg.bounds
        host.view.autoresizingMask = [.width, .height]
        bg.addSubview(host.view)

        p.contentView = bg
        hudPanel = p
        hudHostingController = host
    }

    private func positionPanel() {
        guard let panel = hudPanel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                  ?? NSScreen.main
        guard let s = screen else { return }
        let size = panel.frame.size
        let x = s.visibleFrame.midX - size.width / 2
        let y = s.visibleFrame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activate(_ item: ShortcutItem) {
        guard item.enabled else { return }
        switch item.source {
        case .app:
            dismissHUD()
            MenuEnumerator.activate(item)
        case .system:
            // v0.1: list-only for system shortcuts. Just dismiss.
            dismissHUD()
        }
    }

    // MARK: - HUDDelegate

    func hudMoveSelectionUp()   { hudState.moveSelection(by: -1) }
    func hudMoveSelectionDown() { hudState.moveSelection(by:  1) }
    func hudActivateSelected() {
        if let item = hudState.selectedItem { activate(item) }
    }
    func hudDismiss() { dismissHUD() }
}

/// Keeps Sparkle's update UI visible across the whole session, including
/// when the user switches to another app mid-download. See KB:
/// `conventions/sparkle-integration.md` §6 for the rationale.
final class ShortcutHUDUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private var sessionObserver: NSObjectProtocol?
    private var elevatedWindows: [(window: NSWindow, originalLevel: NSWindow.Level)] = []

    func standardUserDriverWillShowModalAlert() {
        bringForward()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        startFocusGuard()
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFocusGuard()
    }

    private func bringForward() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        elevateAllWindows()
    }

    private func startFocusGuard() {
        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringForward()
        }
    }

    private func stopFocusGuard() {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionObserver = nil
        }
        for entry in elevatedWindows {
            entry.window.level = entry.originalLevel
        }
        elevatedWindows.removeAll()
    }

    private func elevateAllWindows() {
        for window in NSApp.windows where window.isVisible && window.level == .normal {
            elevatedWindows.append((window, window.level))
            window.level = .floating
        }
    }
}

import SwiftUI
import AppKit

struct ShortcutHUDSettingsContent: View {
    let delegate: AppDelegate
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var inputMonitoringGranted: Bool = HotkeyTap.current != nil

    var body: some View {
        Group {
            Section("Keyboard Shortcut") {
                JorvikShortcutRecorder(
                    label: "Show shortcut HUD",
                    keyCode: Binding(
                        get: { delegate.activationKeyCode },
                        set: { delegate.activationKeyCode = $0 }
                    ),
                    modifiers: Binding(
                        get: { delegate.activationModifiers },
                        set: { delegate.activationModifiers = $0 }
                    ),
                    displayString: { delegate.activationDisplayString() },
                    onChanged: { delegate.persistShortcut() },
                    eventTapToDisable: HotkeyTap.current
                )
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if axGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") {
                            _ = AXIsProcessTrustedWithOptions(
                                ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            )
                        }
                        .font(.caption)
                    }
                }
                HStack {
                    Text("Input Monitoring")
                    Spacer()
                    if inputMonitoringGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
                Text("ShortcutHUD needs Accessibility to read app menus and Input Monitoring to listen for the global hotkey. Both are granted in System Settings \u{203A} Privacy & Security.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshPermissionState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
    }

    private func refreshPermissionState() {
        axGranted = AXIsProcessTrusted()
        inputMonitoringGranted = HotkeyTap.current != nil
    }
}

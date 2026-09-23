import SwiftUI
import AppKit

struct ShortcutHUDSettingsContent: View {
    let delegate: AppDelegate
    /// Both kept current by JorvikKit — see `JorvikPermissionWatcher`. Accessibility has a
    /// system announcement; Input Monitoring has none, and here it is inferred from whether
    /// the event tap could actually be created, which is the only thing that matters to us.
    @StateObject private var accessibility = JorvikPermissionWatcher.accessibility()
    @StateObject private var inputMonitoring = JorvikPermissionWatcher { HotkeyTap.current != nil }

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
                    onClear: {
                        // There is no menu item that opens the HUD, and there
                        // cannot be: showHUD() reads the frontmost app, so
                        // opening it from this app's own menu would only ever
                        // show this app's menus. Clearing therefore leaves no
                        // way in until a new shortcut is recorded here, which
                        // the README now says plainly.
                        delegate.activationKeyCode = 0
                        delegate.activationModifiers = []
                        delegate.persistShortcut()
                    },
                    eventTapToDisable: HotkeyTap.current
                )
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if accessibility.isGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") {
                            JorvikPermissionWatcher.promptForAccessibility()
                        }
                        .font(.caption)
                    }
                }
                HStack {
                    Text("Input Monitoring")
                    Spacer()
                    if inputMonitoring.isGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") {
                            JorvikPermissionWatcher.openSettings(pane: .inputMonitoring)
                        }
                        .font(.caption)
                    }
                }
                Text("ShortcutHUD needs Accessibility to read app menus and Input Monitoring to listen for the global hotkey. Both are granted in System Settings \u{203A} Privacy & Security.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MenuBarVisibilitySettings()

            MenuBarPillSettings { delegate.updateHotkeyState() }
        }
    }
}

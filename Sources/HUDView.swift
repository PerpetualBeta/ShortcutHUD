import SwiftUI
import AppKit

@MainActor
@Observable
final class HUDState {
    var query: String = ""
    var items: [ShortcutItem] = []
    var selectedID: UUID?
    /// True when the most recent selection change came from keyboard nav or the
    /// initial clamp, false when it came from mouse hover. The view uses this to
    /// avoid re-centering the scroll view while the user is scrolling — hovering
    /// over rows as they slide under a stationary cursor would otherwise fight
    /// the trackpad input.
    var lastSelectionFromKeyboard: Bool = true

    var filtered: [ShortcutItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.searchHaystack.contains(q) }
    }

    /// Two-level grouping: outer pane (`path[0]`) → inner sections (`path[1]`,
    /// or a single nameless section when items have only one path component).
    /// Captured-app items get nested into File/Edit/View under the app's pane;
    /// other sources collapse to a single nameless inner section.
    var grouped: [HUDPane] {
        let list = filtered
        var paneOrder: [String] = []
        var paneItems: [String: [ShortcutItem]] = [:]
        for item in list {
            let key = item.paneTitle.isEmpty ? "Other" : item.paneTitle
            if paneItems[key] == nil { paneOrder.append(key) }
            paneItems[key, default: []].append(item)
        }
        // Always put the macOS pane last for predictability.
        let macOS = "macOS"
        if paneOrder.contains(macOS) {
            paneOrder.removeAll { $0 == macOS }
            paneOrder.append(macOS)
        }

        return paneOrder.map { pane in
            let items = paneItems[pane] ?? []
            var sectionOrder: [String?] = []
            var sectionItems: [String?: [ShortcutItem]] = [:]
            for item in items {
                let key = item.sectionTitle
                if sectionItems[key] == nil { sectionOrder.append(key) }
                sectionItems[key, default: []].append(item)
            }
            let sections = sectionOrder.map { name in
                HUDPaneSection(name: name, items: sectionItems[name] ?? [])
            }
            return HUDPane(name: pane, sections: sections)
        }
    }

    func clampSelection() {
        let list = filtered
        if list.isEmpty { selectedID = nil; return }
        if selectedID == nil || !list.contains(where: { $0.id == selectedID }) {
            lastSelectionFromKeyboard = true
            selectedID = list.first?.id
        }
    }

    func moveSelection(by delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let currentIndex = list.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = max(0, min(list.count - 1, currentIndex + delta))
        lastSelectionFromKeyboard = true
        selectedID = list[next].id
    }

    var selectedItem: ShortcutItem? {
        guard let id = selectedID else { return nil }
        return filtered.first { $0.id == id }
    }
}

struct HUDPaneSection: Identifiable {
    let name: String?              // nil = anonymous section (no inner header)
    let items: [ShortcutItem]
    // Stable id derived from name. SwiftUI ForEach must see the same id for
    // a given section across recomputes of `state.grouped`, otherwise it
    // tears the view tree down on every selection change and the scroll
    // view fights the user's gesture.
    var id: String { name ?? "__nil__" }
}

struct HUDPane: Identifiable {
    let name: String
    let sections: [HUDPaneSection]
    var id: String { name }
}

struct HUDView: View {
    let state: HUDState
    let onActivate: (ShortcutItem) -> Void
    @FocusState private var searchFocused: Bool
    /// Last cursor position seen by an onHover. Used to ignore "phantom"
    /// hover events that fire when rows slide under a stationary cursor
    /// during a scroll — those would otherwise churn `selectedID` and
    /// trigger re-renders that fight the user's gesture.
    @State private var lastHoverMouseLocation: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter shortcuts\u{2026}", text: Bindable(state).query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($searchFocused)
                    .onChange(of: state.query) { _, _ in state.clampSelection() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    // Eager VStack (not Lazy): pane count is tiny (<20) and a
                    // lazy outer container revises its height estimate as more
                    // panes materialise during scroll, which makes the
                    // scrollbar resize as you drag it.
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(state.grouped) { pane in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pane.name.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)

                                ForEach(pane.sections) { section in
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let sectionName = section.name {
                                            Text(sectionName)
                                                .font(.system(size: 10, weight: .medium))
                                                .tracking(0.4)
                                                .foregroundStyle(.tertiary)
                                                .padding(.horizontal, 14)
                                                .padding(.top, 4)
                                        }
                                        LazyVGrid(
                                            columns: [GridItem(.adaptive(minimum: 340), spacing: 4)],
                                            alignment: .leading,
                                            spacing: 2
                                        ) {
                                            ForEach(section.items) { item in
                                                ShortcutRow(
                                                    item: item,
                                                    isSelected: item.id == state.selectedID
                                                )
                                                .id(item.id)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    if item.enabled { onActivate(item) }
                                                }
                                                .onHover { hovering in
                                                    guard hovering else { return }
                                                    let current = NSEvent.mouseLocation
                                                    guard current != lastHoverMouseLocation else { return }
                                                    lastHoverMouseLocation = current
                                                    state.lastSelectionFromKeyboard = false
                                                    state.selectedID = item.id
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 6)
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                        }

                        if state.filtered.isEmpty {
                            Text(state.items.isEmpty ? "No shortcuts found." : "No matches.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: state.selectedID) { _, newID in
                    guard let id = newID, state.lastSelectionFromKeyboard else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Text("\(state.filtered.count) shortcut\(state.filtered.count == 1 ? "" : "s")")
                Spacer()
                Label("Enter", systemImage: "return").labelStyle(.titleOnly)
                Text("activate").foregroundStyle(.secondary)
                Text("\u{2022}")
                Text("Esc").bold()
                Text("close").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.clampSelection()
            searchFocused = true
        }
    }
}

private struct ShortcutRow: View {
    let item: ShortcutItem
    let isSelected: Bool

    private var keyEquivalent: String {
        switch item.source {
        case .app:
            return ShortcutFormatter.appMenu(
                modifiers: item.modifiers,
                cmdChar: item.cmdChar,
                virtualKey: item.virtualKey,
                glyph: item.glyph
            )
        case .system:
            return ShortcutFormatter.system(
                keyCode: item.virtualKey,
                modifiers: item.modifiers,
                cmdChar: item.cmdChar
            )
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(item.fullTitle)
                .font(.system(size: 15))
                .foregroundStyle(item.enabled ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 14)
            Text(keyEquivalent)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(item.enabled ? Color.secondary : Color.secondary.opacity(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.horizontal, 9)
        )
    }
}

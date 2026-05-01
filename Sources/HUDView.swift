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

    var grouped: [(group: String, items: [ShortcutItem])] {
        let list = filtered
        var order: [String] = []
        var bucket: [String: [ShortcutItem]] = [:]
        for item in list {
            let key = item.groupTitle.isEmpty ? "Other" : item.groupTitle
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(item)
        }
        // Always put macOS section last for predictability.
        let macOS = "macOS"
        if order.contains(macOS) {
            order.removeAll { $0 == macOS }
            order.append(macOS)
        }
        return order.map { ($0, bucket[$0] ?? []) }
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

struct HUDView: View {
    let state: HUDState
    let onActivate: (ShortcutItem) -> Void
    @FocusState private var searchFocused: Bool

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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(state.grouped.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.group.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)

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
                                            if hovering {
                                                state.lastSelectionFromKeyboard = false
                                                state.selectedID = item.id
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.bottom, 8)
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
                keyCode: item.virtualKey ?? 0,
                modifiers: item.modifiers
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

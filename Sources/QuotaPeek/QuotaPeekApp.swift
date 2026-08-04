import SwiftUI

@main
struct QuotaPeekApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(state: state)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if !state.menuBarItems.isEmpty {
            MenuBarSummaryImage(items: state.menuBarItems)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(menuBarAccessibilityLabel)
        } else {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .accessibilityLabel("QuotaPeek")
        }
    }

    private var menuBarAccessibilityLabel: String {
        let summaries = state.menuBarItems.map {
            "\($0.provider.displayName) \($0.value.accessibilityText)"
        }
        return "QuotaPeek, \(summaries.joined(separator: ", "))"
    }
}

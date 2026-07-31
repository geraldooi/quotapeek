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
        if let text = state.menuBarText {
            Label(text, systemImage: "gauge.with.dots.needle.67percent")
        } else {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .accessibilityLabel("QuotaPeek")
        }
    }
}

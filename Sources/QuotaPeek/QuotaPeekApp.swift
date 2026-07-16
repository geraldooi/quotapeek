import SwiftUI

@main
struct QuotaPeekApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(state: state)
        } label: {
            Label(state.menuBarText, systemImage: "gauge.with.dots.needle.67percent")
        }
        .menuBarExtraStyle(.window)
    }
}

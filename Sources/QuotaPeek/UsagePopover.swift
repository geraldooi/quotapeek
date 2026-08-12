import AppKit
import Foundation
import SwiftUI
import QuotaPeekCore

struct UsagePopover: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshRotation = 0.0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    if state.providerVisibility.showsCodex {
                        ProviderCard(
                            snapshot: state.codex,
                            tint: .blue,
                            resetForecast: state.codexResetForecast,
                            appVersion: versionLabel,
                            onRefresh: { state.refresh() },
                            onEnableClaudeQuota: nil
                        )
                    }
                    if state.providerVisibility.showsClaude {
                        ProviderCard(
                            snapshot: state.claude,
                            tint: .orange,
                            resetForecast: nil,
                            appVersion: versionLabel,
                            onRefresh: { state.refresh() },
                            onEnableClaudeQuota: state.isClaudeQuotaIntegrationEnabled
                                ? nil
                                : { state.setClaudeQuotaIntegrationEnabled(true) }
                        )
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            footer
        }
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quota usage")
                    .font(.headline)
                Text(state.providerVisibility.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.refreshSummary)
                    .font(.caption2)
                    .foregroundStyle(summaryColor)
                    .accessibilityLabel("Status: \(state.refreshSummary)")
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
                        refreshRotation += 360
                    }
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(refreshRotation))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Refresh usage")
                .accessibilityLabel(
                    state.isRefreshing ? "Refreshing quota usage" : "Refresh quota usage"
                )
                .disabled(state.isRefreshing)

                settingsMenu
            }
        }
        .padding(16)
    }

    private var settingsMenu: some View {
        Menu {
            Section("Providers") {
                providerToggle(.codex)
                providerToggle(.claude)
            }

            Section("Claude Code") {
                Toggle(
                    "Claude quota bars",
                    isOn: Binding(
                        get: { state.isClaudeQuotaIntegrationEnabled },
                        set: { state.setClaudeQuotaIntegrationEnabled($0) }
                    )
                )
            }

            Section("Menu bar summary") {
                Picker(
                    "Menu bar summary",
                    selection: Binding(
                        get: { state.menuBarSummaryMode },
                        set: { state.setMenuBarSummaryMode($0) }
                    )
                ) {
                    ForEach(MenuBarSummaryMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                            .disabled(!state.isMenuBarSummaryModeAvailable(mode))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "gearshape")
                .frame(width: 18, height: 18)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .contentShape(Rectangle())
        .help("Settings")
        .accessibilityLabel("QuotaPeek settings")
    }

    private var summaryColor: Color {
        if state.isRefreshing {
            return .secondary
        }
        return state.visibleSnapshots.contains(where: \.needsAttention) ? .orange : .secondary
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                if let lastRefresh = state.lastRefresh {
                    Text("Updated")
                    Text(lastRefresh, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("QuotaPeek version \(versionLabel)")
                .fixedSize()

            if let update = state.availableUpdate {
                Link(destination: update.url) {
                    Label("Update", systemImage: "arrow.down.circle")
                }
                .font(.caption2)
                .fixedSize()
                .help("QuotaPeek v\(update.version) is available")
                .accessibilityLabel(
                    "Update available: QuotaPeek version \(update.version). Open the release page"
                )
            }

            Button("Quit") {
                state.quit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private func providerToggle(_ provider: Provider) -> some View {
        let isVisible = state.providerVisibility.contains(provider)
        return Toggle(
            provider.displayName,
            isOn: Binding(
                get: { state.providerVisibility.contains(provider) },
                set: { state.setProvider(provider, isVisible: $0) }
            )
        )
        .disabled(state.isRefreshing || (isVisible && state.providerVisibility.visibleProviders.count == 1))
    }

    private var versionLabel: String {
        AppVersion.label
    }
}

private struct ProviderCard: View {
    let snapshot: UsageSnapshot
    let tint: Color
    let resetForecast: CodexResetForecast?
    let appVersion: String
    let onRefresh: () -> Void
    let onEnableClaudeQuota: (() -> Void)?

    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogo(provider: snapshot.provider)
                    .frame(width: 28, height: 28)

                Text(snapshot.provider.displayName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                ProviderStatusBadge(provider: snapshot.provider, health: snapshot.health)
            }

            if snapshot.health == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Checking local usage…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            "Checking \(snapshot.provider.displayName) local usage"
                        )
                }
                .padding(.vertical, 8)
            } else {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { index, window in
                    UsageWindowRow(
                        window: window,
                        tint: tint,
                        resetForecast: index == snapshot.windows.count - 1 ? resetForecast : nil
                    )
                }

                if let issue = snapshot.issue {
                    UsageIssueView(
                        provider: snapshot.provider,
                        issue: issue,
                        canShowDiagnostics: snapshot.diagnostics != nil,
                        onRefresh: onRefresh,
                        onEnableClaudeQuota: onEnableClaudeQuota,
                        onShowDiagnostics: { showsDiagnostics = true }
                    )
                }
            }
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticsSheet(snapshot: snapshot, appVersion: appVersion)
        }
    }
}

private struct ProviderStatusBadge: View {
    let provider: Provider
    let health: UsageHealth

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel("\(provider.displayName) status: \(label)")
    }

    private var label: String {
        switch health {
        case .loading: "Loading"
        case .ready: "Working"
        case .inactive: "Inactive"
        case .limited: "Limited"
        case .needsAttention: "Needs attention"
        }
    }

    private var icon: String {
        switch health {
        case .loading: "ellipsis.circle"
        case .ready: "checkmark.circle.fill"
        case .inactive: "minus.circle.fill"
        case .limited, .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch health {
        case .loading, .inactive: .secondary
        case .ready: .green
        case .limited, .needsAttention: .orange
        }
    }
}

private struct UsageIssueView: View {
    let provider: Provider
    let issue: UsageIssue
    let canShowDiagnostics: Bool
    let onRefresh: () -> Void
    let onEnableClaudeQuota: (() -> Void)?
    let onShowDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accentColor)

            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(issue.recoverySuggestion)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(
                    onEnableClaudeQuota == nil ? "Try again" : "Enable quota bars",
                    action: onEnableClaudeQuota ?? onRefresh
                )
                    .buttonStyle(.link)
                    .accessibilityLabel(
                        onEnableClaudeQuota == nil
                            ? "Try \(provider.displayName) again"
                            : "Enable Claude Code quota bars"
                    )

                if canShowDiagnostics {
                    Button("View diagnostics", action: onShowDiagnostics)
                        .buttonStyle(.link)
                        .accessibilityLabel("View \(provider.displayName) diagnostics")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9))
    }

    private var isInactive: Bool {
        issue.kind == .noRecentActivity
    }

    private var icon: String {
        isInactive ? "clock.fill" : "exclamationmark.triangle.fill"
    }

    private var accentColor: Color {
        isInactive ? .secondary : .orange
    }

    private var backgroundColor: Color {
        isInactive ? Color.secondary.opacity(0.08) : Color.orange.opacity(0.08)
    }
}

private struct DiagnosticsSheet: View {
    let snapshot: UsageSnapshot
    let appVersion: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.provider.displayName) diagnostics")
                        .font(.headline)
                    Text("Safe to include in a bug report")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )

            HStack {
                Button(copied ? "Copied" : "Copy diagnostic report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }

                Link(
                    "Report issue",
                    destination: URL(string: "https://github.com/geraldooi/quotapeek/issues/new")!
                )

                Spacer()
            }
        }
        .padding(18)
        .frame(width: 460, height: 340)
    }

    private var report: String {
        snapshot.diagnostics?.report(
            provider: snapshot.provider,
            health: snapshot.health,
            issue: snapshot.issue,
            appVersion: appVersion
        ) ?? """
        QuotaPeek \(appVersion)
        Provider: \(snapshot.provider.displayName)
        Status: Diagnostics unavailable

        Privacy: This report does not include prompts, responses, credentials, or usernames.
        """
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let tint: Color
    let resetForecast: CodexResetForecast?

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let used = window.usedPercent {
                    Text("\(UsageFormatting.percent(used)) used")
                        .font(.caption.weight(.medium))
                } else if let tokens = window.tokens {
                    Text("\(UsageFormatting.tokens(tokens)) tokens")
                        .font(.caption.weight(.medium))
                }
            }

            if let used = window.usedPercent {
                ProgressView(value: used, total: 100)
                    .tint(progressTint(for: used))
                    .accessibilityHidden(true)

                HStack {
                    if let remaining = window.remainingPercent {
                        Text("\(UsageFormatting.percent(remaining)) remaining")
                    }
                    Spacer()
                    if let resetAt = window.resetAt {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(UsageFormatting.reset(resetAt))

                            if let resetForecast {
                                Text(resetForecast.compactLabel)
                                    .help(
                                        "Transparent heuristic from willcodexquotareset.com, not an official OpenAI forecast"
                                    )
                                    .accessibilityLabel(resetForecast.accessibilityLabel)
                            }
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [window.label]
        if let used = window.usedPercent {
            parts.append("\(UsageFormatting.percent(used)) used")
        } else if let tokens = window.tokens {
            parts.append("\(UsageFormatting.tokens(tokens)) tokens")
        }
        if let remaining = window.remainingPercent {
            parts.append("\(UsageFormatting.percent(remaining)) remaining")
        }
        if let resetAt = window.resetAt {
            parts.append(UsageFormatting.reset(resetAt))
        }
        if let resetForecast {
            parts.append(resetForecast.accessibilityLabel)
        }
        return parts.joined(separator: ", ")
    }

    private func progressTint(for used: Double) -> Color {
        if used >= 90 { return .red }
        if used >= 75 { return .orange }
        return tint
    }
}

import AppKit
import Foundation
import SwiftUI
import QuotaPeekCore

struct UsagePopover: View {
    @ObservedObject var state: AppState
    @State private var refreshRotation = 0.0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ProviderCard(
                        snapshot: state.codex,
                        tint: .blue,
                        resetForecast: state.codexResetForecast,
                        appVersion: versionLabel,
                        onRefresh: { state.refresh() }
                    )
                    ProviderCard(
                        snapshot: state.claude,
                        tint: .orange,
                        resetForecast: nil,
                        appVersion: versionLabel,
                        onRefresh: { state.refresh() }
                    )
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
                Text("Token usage")
                    .font(.headline)
                Text("Codex and Claude Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.refreshSummary)
                    .font(.caption2)
                    .foregroundStyle(summaryColor)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.6)) {
                    refreshRotation += 360
                }
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(.plain)
            .help("Refresh usage")
            .accessibilityLabel("Refresh token usage")
            .disabled(state.isRefreshing)
        }
        .padding(16)
    }

    private var summaryColor: Color {
        if state.isRefreshing {
            return .secondary
        }
        return state.codex.needsAttention || state.claude.needsAttention ? .orange : .secondary
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

            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("QuotaPeek version \(versionLabel)")
                .fixedSize()

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

    private var versionLabel: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return "Development"
        }

        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVersion.isEmpty ? "Development" : "v\(trimmedVersion)"
    }
}

private struct ProviderCard: View {
    let snapshot: UsageSnapshot
    let tint: Color
    let resetForecast: CodexResetForecast?
    let appVersion: String
    let onRefresh: () -> Void

    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProviderLogo(provider: snapshot.provider)
                    .frame(width: 28, height: 28)

                Text(snapshot.provider.displayName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                ProviderStatusBadge(health: snapshot.health)
            }

            if snapshot.health == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking local usage…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                        issue: issue,
                        canShowDiagnostics: snapshot.diagnostics != nil,
                        onRefresh: onRefresh,
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
    let health: UsageHealth

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch health {
        case .loading: "Loading"
        case .ready: "Working"
        case .limited: "Limited"
        case .needsAttention: "Needs attention"
        }
    }

    private var icon: String {
        switch health {
        case .loading: "ellipsis.circle"
        case .ready: "checkmark.circle.fill"
        case .limited, .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch health {
        case .loading: .secondary
        case .ready: .green
        case .limited, .needsAttention: .orange
        }
    }
}

private struct UsageIssueView: View {
    let issue: UsageIssue
    let canShowDiagnostics: Bool
    let onRefresh: () -> Void
    let onShowDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)

            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(issue.recoverySuggestion)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Try again", action: onRefresh)
                    .buttonStyle(.link)

                if canShowDiagnostics {
                    Button("View diagnostics", action: onShowDiagnostics)
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
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

private struct ProviderLogo: View {
    let provider: Provider

    var body: some View {
        if let image = logoImage {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
    }

    private var logoImage: NSImage? {
        let resourceName = provider == .codex ? "codex" : "claude-code"
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "BrandIcons"
        ) ?? Bundle.module.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "BrandIcons"
        ) ?? Bundle.module.url(forResource: resourceName, withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
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

                HStack {
                    if let remaining = window.remainingPercent {
                        Text("\(UsageFormatting.percent(remaining)) remaining")
                    }
                    Spacer()
                    if let resetAt = window.resetAt {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(UsageFormatting.reset(resetAt))

                            if let resetForecast {
                                (
                                    Text("\(resetForecast.score)%").fontWeight(.medium)
                                    + Text(" chance · next 48h")
                                )
                                .help("Unofficial estimate from willcodexquotareset.com")
                                .accessibilityLabel(
                                    "\(resetForecast.score) percent chance of a Codex reset in the next 48 hours"
                                )
                            }
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func progressTint(for used: Double) -> Color {
        if used >= 90 { return .red }
        if used >= 75 { return .orange }
        return tint
    }
}

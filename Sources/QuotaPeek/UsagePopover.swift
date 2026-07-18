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
                        resetForecast: state.codexResetForecast
                    )
                    ProviderCard(snapshot: state.claude, tint: .orange, resetForecast: nil)
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
            .disabled(state.isRefreshing)
        }
        .padding(16)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.provider == .codex ? "chevron.left.forwardslash.chevron.right" : "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(snapshot.provider.displayName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if snapshot.isAvailable {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }
            }

            if snapshot.isAvailable {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { index, window in
                    UsageWindowRow(
                        window: window,
                        tint: tint,
                        resetForecast: index == snapshot.windows.count - 1 ? resetForecast : nil
                    )
                }
            } else {
                Text(snapshot.statusMessage ?? "Usage unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
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

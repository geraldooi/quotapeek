import SwiftUI
import QuotaPeekCore

struct UsagePopover: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ProviderCard(snapshot: state.codex, tint: .blue)
                    ProviderCard(snapshot: state.claude, tint: .orange)
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .frame(width: 360, height: 480)
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
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(state.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        state.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: state.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh usage")
            .disabled(state.isRefreshing)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if let lastRefresh = state.lastRefresh {
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(lastRefresh, style: .relative)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                state.quit()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
    }
}

private struct ProviderCard: View {
    let snapshot: UsageSnapshot
    let tint: Color

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
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageWindowRow(window: window, tint: tint)
                }

                tokenBreakdown
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

    private var tokenBreakdown: some View {
        HStack(spacing: 0) {
            TokenMetric(label: "Input", value: snapshot.tokens.input)
            Divider().frame(height: 28)
            TokenMetric(label: "Cached", value: snapshot.tokens.cachedInput)
            Divider().frame(height: 28)
            TokenMetric(label: "Output", value: snapshot.tokens.output)
        }
        .padding(.top, 2)
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let tint: Color

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
                        Text(UsageFormatting.reset(resetAt))
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

private struct TokenMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(UsageFormatting.tokens(value))
                .font(.system(size: 12, weight: .medium, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

struct UsageBar: View {
    @AppStorage("usageBarCollapsed") private var isCollapsed = false
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(UsageStore.self) private var usage
    @State private var showsDetails = false

    var body: some View {
        Group {
            if !usage.connectedProviders.isEmpty {
                HStack(alignment: isCollapsed ? .center : .top, spacing: 6) {
                    Button { showsDetails = true } label: {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if isCollapsed {
                                HStack(spacing: 14) {
                                    ForEach(usage.connectedProviders) { provider in
                                        UsageCollapsedItem(provider: provider, state: usage.state(for: provider))
                                    }
                                    Spacer(minLength: 0)
                                }
                            } else {
                                VStack(spacing: 9) {
                                    ForEach(usage.connectedProviders) { provider in
                                        UsageBarRow(provider: provider, state: usage.state(for: provider), now: context.date)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Afficher le détail de l’usage")
                    .accessibilityHint("Affiche le détail de l’usage")
                    Button { withAnimation(.snappy(duration: 0.2)) { isCollapsed.toggle() } } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isCollapsed ? "Afficher le détail des limites" : "Réduire l’usage")
                    .accessibilityLabel(isCollapsed ? "Développer l’usage" : "Réduire l’usage")
                }
                .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, isCollapsed ? 8 : 10)
            } else if usage.isSignedOutEverywhere {
                UsageSignedOutRow(isWaiting: !usage.pendingSignIns.isEmpty) { showsDetails = true }
            }
        }
        .sheet(isPresented: $showsDetails) {
            UsageSheet().environment(workspace).environment(usage)
        }
    }
}

private struct UsageSignedOutRow: View {
    let isWaiting: Bool
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(isWaiting ? "En attente de la connexion…" : "Usage des agents")
            Spacer(minLength: 4)
            if isWaiting { ProgressView().controlSize(.mini) }
            else { Button("Se connecter…", action: showDetails).buttonStyle(.link) }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct UsageBarRow: View {
    let provider: UsageProvider
    let state: UsageState
    let now: Date

    private var windows: [UsageWindow] {
        guard let usage = state.usage else { return [] }
        let preferred = [usage.session, usage.weekly].compactMap { $0 }
        return preferred.isEmpty ? Array(usage.windows.prefix(2)) : preferred
    }
    private var countdown: String? {
        state.usage?.headline?.resetText(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                UsageProviderLogo(provider: provider, size: 12)
                Text(provider.title).fontWeight(.medium)
                if state.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(state.error ?? "")
                }
                Spacer(minLength: 4)
                if let countdown {
                    Label(countdown, systemImage: "arrow.clockwise")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            HStack(spacing: 10) {
                ForEach(windows) { window in
                    UsageCompactMeter(window: window)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let parts = windows.map { "\($0.kind.title) : \($0.percentText) utilisés" }
        let reset = countdown.map { ", réinitialisation dans \($0)" } ?? ""
        return "\(provider.title), " + parts.joined(separator: ", ") + reset
    }
}

private struct UsageCollapsedItem: View {
    let provider: UsageProvider
    let state: UsageState

    private var window: UsageWindow? { state.usage?.headline }

    var body: some View {
        HStack(spacing: 5) {
            UsageProviderLogo(provider: provider, size: 13)
            if let window {
                Text(window.percentText)
                    .monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Color.secondary : window.level.tint)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
            if state.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(state.error ?? "")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.map { "\(provider.title), \($0.kind.title) : \($0.percentText) utilisés" } ?? "\(provider.title), usage indisponible")
    }
}

private struct UsageCompactMeter: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 5) {
            Text(window.kind.shortTitle).foregroundStyle(.secondary)
            UsageGauge(fraction: window.fraction, level: window.level)
            Text(window.percentText)
                .monospacedDigit()
                .foregroundStyle(window.level == .comfortable ? Color.secondary : window.level.tint)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .font(.system(size: 10))
    }
}

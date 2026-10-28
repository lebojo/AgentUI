import SwiftUI

struct UsageBar: View {
    @AppStorage("usageBarCollapsed") private var isCollapsed = false
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(UsageStore.self) private var usage
    @State private var showsDetails = false

    var body: some View {
        Group {
            if !usage.connectedProviders.isEmpty {
                HStack(alignment: isCollapsed ? .center : .top, spacing: Spacing.s) {
                    Button { showsDetails = true } label: {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if isCollapsed {
                                HStack(spacing: Spacing.l) {
                                    ForEach(usage.connectedProviders) { provider in
                                        UsageCollapsedItem(provider: provider, state: usage.state(for: provider))
                                    }
                                    Spacer(minLength: 0)
                                }
                            } else {
                                VStack(spacing: Spacing.m) {
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
                    Button { withAnimation(Motion.standard) { isCollapsed.toggle() } } label: {
                        Image(systemName: "chevron.down")
                            .font(Typography.xxs.weight(.semibold))
                            .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                            .frame(width: IconSize.s, height: IconSize.s)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .help(isCollapsed ? "Afficher le détail des limites" : "Réduire l’usage")
                    .accessibilityLabel(isCollapsed ? "Développer l’usage" : "Réduire l’usage")
                }
                .padding(.leading, Spacing.l).padding(.trailing, Spacing.m).padding(.vertical, Spacing.m)
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
        HStack(spacing: Spacing.s) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(isWaiting ? "En attente de la connexion…" : "Usage des agents")
            Spacer(minLength: Spacing.xs)
            if isWaiting { ProgressView().controlSize(.mini) }
            else { Button("Se connecter…", action: showDetails).buttonStyle(.link) }
        }
        .font(Typography.s).foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                UsageProviderLogo(provider: provider, size: IconSize.xs)
                Text(provider.title).fontWeight(.medium)
                if state.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                        .help(state.error ?? "")
                }
                Spacer(minLength: Spacing.xs)
                if let countdown {
                    Label(countdown, systemImage: "arrow.clockwise")
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.s)
            HStack(spacing: Spacing.m) {
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
        HStack(spacing: Spacing.xs) {
            UsageProviderLogo(provider: provider, size: IconSize.xs)
            if let window {
                Text(window.percentText)
                    .monospacedDigit()
                    .foregroundStyle(window.level == .comfortable ? Palette.textSecondary : window.level.tint)
            } else {
                Text("—").foregroundStyle(Palette.textSecondary)
            }
            if state.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    .help(state.error ?? "")
            }
        }
        .font(Typography.s.weight(.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.map { "\(provider.title), \($0.kind.title) : \($0.percentText) utilisés" } ?? "\(provider.title), usage indisponible")
    }
}

private struct UsageCompactMeter: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(window.kind.shortTitle).foregroundStyle(Palette.textSecondary)
            UsageGauge(fraction: window.fraction, level: window.level)
            Text(window.percentText)
                .monospacedDigit()
                .foregroundStyle(window.level == .comfortable ? Palette.textSecondary : window.level.tint)
                .frame(minWidth: Dimension.Usage.percentMinWidth, alignment: .trailing)
        }
        .font(Typography.xs)
    }
}

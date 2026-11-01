import SwiftUI

struct UsageSheet: View {
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("Usage des agents").font(Typography.title)
                    Spacer()
                    if usage.isRefreshing { ProgressView().controlSize(.small) }
                    Button { Task { await usage.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(usage.isRefreshing)
                        .help("Actualiser")
                        .accessibilityLabel("Actualiser l’usage")
                }
                ForEach(UsageProvider.allCases) { provider in
                    UsageProviderSection(provider: provider, state: usage.state(for: provider), now: context.date)
                }
                HStack {
                    if let lastRefresh = usage.lastRefresh {
                        Text("Mis à jour \(lastRefresh.formatted(.relative(presentation: .named)))")
                            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xxl)
            .frame(width: Dimension.Sheet.width)
        }
    }
}

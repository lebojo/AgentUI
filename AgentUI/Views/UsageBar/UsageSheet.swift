import SwiftUI

struct UsageSheet: View {
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("Agent Usage").font(Typography.title)
                    Spacer()
                    if usage.isRefreshing { ProgressView().controlSize(.small) }
                    Button { Task { await usage.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(usage.isRefreshing)
                        .help("Refresh")
                        .accessibilityLabel("Refresh Usage")
                }
                ForEach(usage.providers) { provider in
                    UsageProviderSection(provider: provider, state: usage.state(for: provider), now: context.date)
                }
                HStack {
                    if let lastRefresh = usage.lastRefresh {
                        Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
                            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xxl)
            .frame(width: Dimension.Sheet.width)
        }
    }
}

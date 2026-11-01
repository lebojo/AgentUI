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
                    .help("Show usage details")
                    .accessibilityHint("Shows usage details")

                    Button { withAnimation(Motion.standard) { isCollapsed.toggle() } } label: {
                        Image(systemName: "chevron.down")
                            .font(Typography.xxs.weight(.semibold))
                            .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                            .frame(width: IconSize.s, height: IconSize.s)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .help(isCollapsed ? "Show limit details" : "Collapse Usage")
                    .accessibilityLabel(isCollapsed ? "Expand Usage" : "Collapse Usage")
                }
                .padding(.leading, Spacing.l).padding(.trailing, Spacing.m).padding(.vertical, isCollapsed ? Spacing.m : Spacing.l)
            } else if usage.isSignedOutEverywhere {
                UsageSignedOutRow(isWaiting: !usage.pendingSignIns.isEmpty) { showsDetails = true }
            }
        }
        .sheet(isPresented: $showsDetails) {
            UsageSheet().environment(workspace).environment(usage)
        }
    }
}

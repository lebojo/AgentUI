import SwiftUI

struct SidebarWorkInProgressItemRow: View {
    @Environment(WorkspaceStore.self) private var store

    let item: WorkInProgressItem
    let isSelected: Bool

    var body: some View {
        Button { store.selection = item.id } label: {
            HStack(spacing: Spacing.s) {
                TerminalIcon(agent: item.agent)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.name).lineLimit(1)
                    Text(item.location)
                        .font(Typography.s).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: Spacing.xs)
            }
            .padding(.vertical, Spacing.xxs).padding(.horizontal, Spacing.xs)
            .background(isSelected ? Palette.selectionFill : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.location)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.location)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

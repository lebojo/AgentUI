import SwiftUI

struct GitChangeRow: View {
    @Environment(InspectorPreviews.self) private var previews

    let change: GitChange
    let root: String
    let scope: GitChangeScope
    let source: any InspectorSource

    private var kind: GitChangeKind { scope.kind(of: change) }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button {
                previews.diff(change, in: scope, at: root)
            } label: {
                HStack(spacing: Spacing.s) {
                    Label(change.name, systemImage: "doc").lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Spacing.xs)
                    Text(kind.letter).font(Typography.captionMono).foregroundStyle(kind.color)
                        .frame(width: Dimension.Inspector.statusColumnWidth).accessibilityLabel(kind.title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Show diff for \(change.path)")
            if source.canWriteRepository, let action = scope.action(for: change) {
                GitActionButton(action: action, root: root, source: source)
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .accessibilityLabel(action.title + " " + change.name)
            }
        }
        .font(Typography.body)
    }
}

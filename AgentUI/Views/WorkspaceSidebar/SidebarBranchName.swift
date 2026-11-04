import SwiftUI

struct SidebarBranchName: View {
    let branch: GitBranch
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: branch.symbolName).font(Typography.xxs)
            Text(branch.name).lineLimit(1).truncationMode(.middle)
        }
        .font(Typography.s)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(branch.accessibilityLabel)
    }
}

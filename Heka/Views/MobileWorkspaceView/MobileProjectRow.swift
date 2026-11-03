import SwiftUI

struct MobileProjectRow: View {
    @State private var expanded = true

    let project: Project

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(project.worktrees) { worktree in
                MobileWorktreeRow(worktree: worktree)
            }
        } label: {
            Label(project.name, systemImage: project.appearance.displaySymbol.systemName)
        }
        .selectionDisabled()
    }
}

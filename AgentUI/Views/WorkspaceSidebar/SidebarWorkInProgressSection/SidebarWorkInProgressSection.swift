import SwiftUI

struct SidebarWorkInProgressSection: View {
    @Environment(WorkspaceStore.self) private var store

    let query: String

    private var rows: [WorkInProgressRow] {
        WorkInProgress.groups(store.workInProgress, matching: query).flatMap(\.rows)
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            Section(isExpanded: query.isEmpty ? Bindable(store)[expanded: WorkInProgress.expansionID] : .constant(true)) {
                let selected = store.selection.map(WorkInProgressRow.ID.terminal)
                ForEach(rows) { row in
                    SidebarWorkInProgressRow(row: row, isSelected: row.id == selected)
                }
            } header: {
                Text("Work in Progress")
            }
        }
    }
}

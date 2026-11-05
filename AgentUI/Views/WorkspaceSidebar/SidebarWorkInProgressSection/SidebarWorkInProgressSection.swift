import SwiftUI

struct SidebarWorkInProgressSection: View {
    @Environment(WorkspaceStore.self) private var store

    let query: String

    private var rows: [WorkInProgressRow] {
        query.isEmpty ? store.workInProgressRows : WorkInProgress.groups(store.workInProgress, matching: query).flatMap(\.rows)
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            Section(isExpanded: query.isEmpty ? Bindable(store)[expanded: WorkInProgress.expansionID] : .constant(true)) {
                ForEach(rows) { row in
                    SidebarWorkInProgressRow(row: row)
                }
            } header: {
                Text("Work in Progress")
            }
        }
    }
}

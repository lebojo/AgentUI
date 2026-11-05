import SwiftUI

struct SidebarWorkInProgressSection: View {
    @Environment(WorkspaceStore.self) private var store

    let query: String

    private var groups: [WorkInProgressGroup] { WorkInProgress.groups(store.workInProgress, matching: query) }

    var body: some View {
        let groups = groups
        if !groups.isEmpty {
            Section(isExpanded: query.isEmpty ? Bindable(store)[expanded: WorkInProgress.expansionID] : .constant(true)) {
                ForEach(groups) { group in
                    SidebarStatusHeader(status: group.status, count: group.items.count)
                    ForEach(group.items) { item in
                        SidebarWorkInProgressRow(item: item)
                    }
                }
            } header: {
                Text("Work in Progress")
            }
        }
    }
}

import SwiftUI

struct SidebarWorkInProgressSection: View {
    @Bindable var store: WorkspaceStore

    let query: String

    private var groups: [WorkInProgressGroup] {
        WorkInProgress.groups(in: store.projects, statuses: store.sessions.agentStatuses,
                              agents: store.sessions.runningAgents, query: query)
    }

    var body: some View {
        let groups = groups
        if !groups.isEmpty {
            Section(isExpanded: query.isEmpty ? $store[expanded: WorkInProgress.expansionID] : .constant(true)) {
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

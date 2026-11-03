import SwiftUI

struct SidebarSubagentDisclosure<Label: View>: View {
    @Environment(WorkspaceStore.self) private var store

    let expansionID: UUID
    let terminalIDs: [UUID]
    let label: Label

    private var subagents: [Subagent] {
        terminalIDs.flatMap { store.sessions.session($0)?.subagents ?? [] }
            .filter { $0.isVisible || $0.id == store.selection }
    }

    var body: some View {
        let subagents = subagents
        if subagents.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: Bindable(store)[expanded: expansionID]) {
                ForEach(subagents) { subagent in
                    SidebarSubagentRow(subagent: subagent)
                }
            } label: {
                label
            }
        }
    }

    init(expansionID: UUID, terminalIDs: [UUID], @ViewBuilder label: () -> Label) {
        self.expansionID = expansionID
        self.terminalIDs = terminalIDs
        self.label = label()
    }
}

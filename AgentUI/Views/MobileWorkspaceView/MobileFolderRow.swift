import SwiftUI

struct MobileFolderRow: View {
    let group: SidebarFilterResult.Group

    var body: some View {
        DisclosureGroup {
            ForEach(group.subgroups) { subgroup in MobileFolderRow(group: subgroup) }
            ForEach(group.projects) { project in MobileProjectRow(project: project) }
        } label: {
            Label(group.folder.name, systemImage: group.folder.appearance.displaySymbol.systemName)
        }
        .selectionDisabled()
    }
}

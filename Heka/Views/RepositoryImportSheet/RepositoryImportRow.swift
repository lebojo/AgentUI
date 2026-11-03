import SwiftUI

struct RepositoryImportRow: View {
    @State private var expanded = true

    @Binding var selection: Set<String>

    let item: RepositoryImportItem

    private var appearance: SidebarAppearance {
        SidebarAppearance(kind: item.children == nil ? .project : .folder)
    }

    private var toggle: some View {
        Toggle(sources: item.repositoryPaths.map(binding), isOn: \.self) {
            Label {
                Text(item.name).lineLimit(1).truncationMode(.middle)
            } icon: {
                Image(systemName: appearance.displaySymbol.systemName).foregroundStyle(appearance.color)
            }
        }
        .toggleStyle(.checkbox)
        .help(item.path)
    }

    var body: some View {
        if let children = item.children {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(children) { child in
                    RepositoryImportRow(selection: $selection, item: child)
                }
            } label: { toggle }
        } else {
            toggle
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding {
            selection.contains(path)
        } set: { isOn in
            if isOn { selection.insert(path) } else { selection.remove(path) }
        }
    }
}

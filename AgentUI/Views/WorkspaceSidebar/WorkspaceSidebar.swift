import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @State private var search = ""
    @State private var filtered = SidebarFilterResult()

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Projects").font(Typography.headline)
                Spacer()
                Menu {
                    Button("Add Project…", systemImage: "folder.badge.plus") { store.chooseProjects() }
                        .keyboardShortcut("o")
                    Button("Import Folder…", systemImage: "square.and.arrow.down") { store.chooseFolder() }
                    Divider()
                    Button("New Virtual Folder…", systemImage: "folder.badge.plus") { sheet = .folder(parentID: nil) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "plus").frame(width: IconSize.l, height: IconSize.l)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add projects or a virtual folder")
                .accessibilityLabel("Add projects or a virtual folder")
                .disabled(store.isReadOnly || store.isImporting)
            }
            .padding(.horizontal, Spacing.l).padding(.top, Spacing.m)
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
                TextField("Filter projects and terminals", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filter projects and terminals")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.textSecondary).accessibilityLabel("Clear Filter")
                }
            }
            .font(Typography.m)
            .padding(Spacing.m)
            .background(Palette.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.m))
            .padding(.horizontal, Spacing.l).padding(.top, Spacing.m).padding(.bottom, Spacing.l)

            SidebarProjectList(
                sheet: $sheet,
                removal: $removal,
                result: filtered,
                query: search
            )
            SidebarFooter()
        }
        .toolbar {
            ToolbarItem { FloatingTerminalButton() }
        }
        .onChange(of: SidebarFilterInput(folders: store.folders, projects: store.projects, query: search), initial: true) { _, input in
            filtered = input.filtered()
        }
    }
}

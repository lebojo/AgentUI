import SwiftUI
import AppKit

struct WorkspaceWelcomeView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "terminal").font(Typography.heroSymbol).foregroundStyle(Palette.textSecondary)
            Text("A home for your projects").font(Typography.display)
            Text("Group your projects, open terminals\nand work on several branches at once.")
                .font(Typography.l).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).lineSpacing(Spacing.xs)
            HStack(spacing: Spacing.l) {
                Button("Add Project…") { store.chooseProjects() }.buttonStyle(.borderedProminent)
                Button("Import Folder…") { store.chooseFolder() }
            }.padding(.top, Spacing.s)
            Button("Create a Virtual Folder") { presentation.sheet = .folder(parentID: nil) }.buttonStyle(.link).font(Typography.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .navigationTitle("AgentUI")
    }
}

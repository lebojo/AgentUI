import SwiftUI
import AppKit

struct WorkspaceWelcomeView: View {
    @Binding var sheet: WorkspaceSheet?

    let store: WorkspaceStore

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "terminal").font(Typography.heroSymbol).foregroundStyle(Palette.textSecondary)
            Text("Un espace pour tes projets").font(Typography.display)
            Text("Regroupe tes projets, ouvre des terminaux\net travaille sur plusieurs branches à la fois.")
                .font(Typography.l).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).lineSpacing(Spacing.xs)
            HStack(spacing: Spacing.l) {
                Button("Ajouter un projet…") { store.chooseProjects() }.buttonStyle(.borderedProminent)
                Button("Importer un dossier…") { store.chooseFolder() }
            }.padding(.top, Spacing.s)
            Button("Créer un dossier virtuel") { sheet = .folder(parentID: nil) }.buttonStyle(.link).font(Typography.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
        .navigationTitle("AgentUI")
    }
}

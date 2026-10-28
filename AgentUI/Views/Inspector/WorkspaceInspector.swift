import AppKit
import SwiftUI

struct WorkspaceInspector: View {
    @AppStorage("inspectorTab") private var tab: InspectorTab = .files

    @Bindable var store: WorkspaceStore

    var body: some View {
        Group {
            if let context = store.context(for: store.selection) {
                InspectorContents(store: store, context: context, tab: tab)
                    .id(context.worktree.id)
            } else {
                ContentUnavailableView("Aucun terminal sélectionné", systemImage: tab.symbol,
                                       description: Text("Ouvre un terminal pour explorer son projet."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            Picker("Vue du panneau de droite", selection: $tab) {
                ForEach(InspectorTab.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .labelStyle(.iconOnly)
                        .help(item.title)
                        .accessibilityLabel(item.title)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct InspectorContents: View {
    @State private var model = InspectorStore()
    @State private var refresh = 0
    @State private var preview: TextPreview?
    @State private var previewError: String?
    @State private var loadingPreview = false

    @Bindable var store: WorkspaceStore

    let context: TerminalContext
    let tab: InspectorTab

    @ViewBuilder private var githubSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("GitHub").font(Typography.sectionTitle)
            if let github = model.github {
                if let url = URL(string: github.repository.url) { Link(github.repository.nameWithOwner, destination: url).lineLimit(2) }
                if let pr = github.pullRequest {
                    if let url = URL(string: pr.url) { Link("#\(pr.number) · \(pr.title)", destination: url).font(Typography.body) }
                    Text("\(pr.isDraft ? "Brouillon" : pr.state) · \(pr.headRefName) → \(pr.baseRefName)")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                } else if let error = github.pullRequestError {
                    InspectorNotice(title: "Pull request indisponible", message: error)
                } else { Text("Aucune pull request pour cette branche.").font(Typography.body).foregroundStyle(Palette.textSecondary) }
            } else if let error = model.githubError {
                InspectorNotice(title: "Connexion GitHub indisponible", message: error)
            } else { Text("Chargement via gh…").font(Typography.body).foregroundStyle(Palette.textSecondary) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(tab.title).font(Typography.headline)
                    Text(context.worktree.isPrimary ? context.project.name : context.worktree.name)
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(1).help(context.worktree.path)
                }
                Spacer()
                if model.loading || loadingPreview { ProgressView().controlSize(.small) }
                Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Actualiser").accessibilityLabel("Actualiser \(tab.title)")
            }.padding(Spacing.l)
            Divider()
            switch tab {
            case .files:
                List {
                    ExplorerDirectory(url: URL(fileURLWithPath: context.worktree.path), open: openFile)
                }.listStyle(.plain).id(refresh)
            case .agents: AgentConversationList(store: store, context: context, refresh: refresh)
            case .git, .checks:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                        if let local = model.local {
                            if tab == .git { git(local) } else { checks(local) }
                        } else if let error = model.localError {
                            InspectorNotice(title: "Git indisponible", message: error, symbol: "folder.badge.questionmark")
                        } else {
                            Text("Lecture du dépôt…").foregroundStyle(Palette.textSecondary)
                        }
                    }.padding(Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: "\(tab.rawValue)-\(refresh)") {
            guard tab == .git || tab == .checks else { return }
            await model.monitor(path: context.worktree.path, forceRemote: refresh > 0)
        }
        .sheet(item: $preview) { TextPreviewSheet(preview: $0) }
        .alert("Aperçu indisponible", isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) {
            Button("OK") { previewError = nil }
        } message: { Text(previewError ?? "") }
    }

    @ViewBuilder private func git(_ local: LocalGitSnapshot) -> some View {
        if let branch = local.branch { BranchBadge(branch: branch) }
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
            Text("Modifications · \(local.changes.count)").font(Typography.sectionTitle)
            if local.changes.isEmpty {
                Label("Aucune modification locale", systemImage: "checkmark.circle").foregroundStyle(Palette.textSecondary).font(Typography.body)
            }
            ForEach(local.changes) { change in
                Button {
                    loadPreview(title: change.path, url: nil) { try await InspectorService.diff(change, at: local.root) }
                } label: {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Text(change.status).font(Typography.captionMono).foregroundStyle(Palette.textSecondary).frame(width: Dimension.Inspector.statusColumnWidth)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(change.path).font(Typography.body).lineLimit(2).truncationMode(.middle)
                            Text(change.description).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, Spacing.xxs).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Afficher le diff de \(change.path)")
            }
        }
        Divider()
        githubSummary
    }

    @ViewBuilder private func checks(_ local: LocalGitSnapshot) -> some View {
        githubSummary
        if let github = model.github {
            if let pr = github.pullRequest, let checks = pr.statusCheckRollup, !checks.isEmpty {
                Divider()
                Text("Checks de la pull request").font(Typography.sectionTitle)
                if pr.headRefOid != local.headSHA {
                    Label("Ces checks concernent le commit distant de la PR, différent du HEAD local.", systemImage: "info.circle")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(checks) { check in CheckRow(title: check.title, result: check.result, url: check.url) }
            }
            Divider()
            Text("Actions · HEAD local").font(Typography.sectionTitle)
            if let sha = local.headSHA { Text(String(sha.prefix(8))).font(Typography.captionMono).foregroundStyle(Palette.textSecondary) }
            if let error = github.checksError {
                InspectorNotice(title: "Actions indisponibles", message: error)
            } else if github.runs.isEmpty {
                Text(local.headSHA == nil ? "Aucun commit dans ce dépôt." : "Aucune exécution GitHub Actions pour ce commit.")
                    .font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
            ForEach(github.runs) { run in CheckRow(title: run.workflowName.isEmpty ? run.displayTitle : run.workflowName, result: run.result, url: run.url) }
        }
    }

    private func openFile(_ url: URL) {
        loadPreview(title: url.lastPathComponent, url: url) { try await InspectorService.textFile(url) }
    }

    private func loadPreview(title: String, url: URL?, load: @escaping () async throws -> String) {
        guard !loadingPreview else { return }
        loadingPreview = true
        Task { @MainActor in
            defer { loadingPreview = false }
            do { preview = try TextPreview(title: title, text: await load(), url: url) }
            catch { previewError = error.localizedDescription }
        }
    }
}

struct InspectorNotice: View {
    let title: String
    let message: String
    var symbol = "exclamationmark.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(title, systemImage: symbol).font(Typography.label)
            Text(message).font(Typography.caption).foregroundStyle(Palette.textSecondary).textSelection(.enabled)
        }
    }
}

private struct CheckRow: View {
    let title: String
    let result: String
    let url: String?
    private var status: (symbol: String, color: Color, title: String) {
        switch result.uppercased() {
        case "SUCCESS": ("checkmark.circle.fill", Palette.success, "Réussi")
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED": ("xmark.circle.fill", Palette.danger, "Échec")
        case "CANCELLED": ("slash.circle", Palette.textSecondary, "Annulé")
        case "SKIPPED", "NEUTRAL": ("minus.circle", Palette.textSecondary, "Ignoré")
        default: ("clock", Palette.warning, "En attente / en cours")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: status.symbol).foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let url, let destination = URL(string: url) { Link(title, destination: destination) }
                else { Text(title) }
                Text(status.title).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }.font(Typography.body)
        }.padding(.vertical, Spacing.xxs)
    }
}

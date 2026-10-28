import AppKit
import Observation

@MainActor @Observable final class WorkspaceStore {
    private(set) var folders: [ProjectFolder] = []
    private(set) var projects: [Project] = []
    private var collapsed: Set<UUID> = []
    var selection: UUID? {
        didSet { if oldValue != selection { save() } }
    }
    var state: Workspace { Workspace(folders: folders, projects: projects, selection: selection, collapsed: collapsed) }
    private(set) var persistenceError: String?
    private(set) var hasUnsavedChanges = false
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var persistedRevision: UInt64 = 0
    @ObservationIgnored private var failedRevision: UInt64 = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var restoring = false
    private let writer: WorkspaceWriter
    var errorMessage: String?
    var busyProjects: Set<UUID> = []
    private(set) var isImporting = false
    let sessions = TerminalSessions()
    private let fileURL: URL
    private var canSave = true

    init(fileURL: URL = WorkspaceDisk.applicationDirectory.appendingPathComponent("workspace.json")) {
        self.fileURL = fileURL
        writer = WorkspaceWriter(fileURL: fileURL)
        do { restore(try WorkspaceDisk.load(from: fileURL)) }
        catch {
            canSave = false
            errorMessage = "Impossible de lire l’organisation. Le fichier original a été préservé : \(fileURL.path)\n\(error.localizedDescription)"
        }
    }

    var isReadOnly: Bool { !canSave }

    func retryLoading() {
        guard isReadOnly else { return }
        do {
            restore(try WorkspaceDisk.load(from: fileURL))
            canSave = true
            errorMessage = nil
        } catch { errorMessage = "L’organisation reste illisible. Le fichier original est conservé : \(fileURL.path)\n\(error.localizedDescription)" }
    }

    var terminalCount: Int { projects.flatMap(\.worktrees).flatMap(\.terminals).count }

    func context(for terminalID: UUID?) -> TerminalContext? {
        for project in projects {
            for worktree in project.worktrees {
                if let terminal = worktree.terminals.first(where: { $0.id == terminalID }) {
                    return TerminalContext(project: project, worktree: worktree, terminal: terminal)
                }
            }
        }
        return nil
    }

    subscript(expanded id: UUID) -> Bool {
        get { isExpanded(id) }
        set { setExpanded(id, newValue) }
    }

    func isExpanded(_ id: UUID) -> Bool { !collapsed.contains(id) }
    func setExpanded(_ id: UUID, _ expanded: Bool) {
        if expanded { collapsed.remove(id) } else { collapsed.insert(id) }
        save()
    }

    @discardableResult func addFolder(_ name: String, parentID: UUID? = nil) -> UUID {
        let parentID = parentID.flatMap { id in folders.contains { $0.id == id } ? id : nil }
        let folder = ProjectFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), parentID: parentID)
        folders.append(folder)
        if let parentID { revealFolder(parentID) }
        save()
        return folder.id
    }

    func canMoveFolder(_ id: UUID, to parentID: UUID?) -> Bool {
        guard let folder = folders.first(where: { $0.id == id }), folder.parentID != parentID else { return false }
        guard let parentID else { return true }
        return folders.contains { $0.id == parentID } && !folders.subtree(of: id).contains(parentID)
    }

    func moveFolder(_ id: UUID, to parentID: UUID?) {
        guard canMoveFolder(id, to: parentID), let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].parentID = parentID
        if let parentID { revealFolder(parentID) }
        save()
    }

    func drop(_ id: UUID, into folderID: UUID) -> Bool {
        if projects.contains(where: { $0.id == id }) {
            moveProject(id, to: folderID)
            return true
        }
        guard canMoveFolder(id, to: folderID) else { return false }
        moveFolder(id, to: folderID)
        return true
    }

    func appearance(of id: UUID) -> SidebarAppearance? {
        folders.first { $0.id == id }?.appearance ?? projects.first { $0.id == id }?.appearance
    }

    func setAppearance(_ appearance: SidebarAppearance, for id: UUID) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].symbol = appearance.symbol
            folders[index].tint = appearance.tint
        } else if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].symbol = appearance.symbol
            projects[index].tint = appearance.tint
        } else { return }
        save()
    }

    @discardableResult func addProject(_ url: URL, folderID: UUID? = nil) throws -> Project {
        let canonical = URL(fileURLWithPath: WorkspaceDisk.canonicalPath(url))
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &directory), directory.boolValue else {
            throw WorkspaceError(message: "Ce dossier n’est plus accessible : \(canonical.path)")
        }
        if let index = projects.firstIndex(where: { $0.path == canonical.path }) {
            if let folderID { projects[index].folderID = folderID }
            save()
            return projects[index]
        }
        let project = Project(url: canonical, folderID: folderID)
        projects.append(project)
        if selection == nil { selection = project.worktrees.first?.terminals.first?.id }
        save()
        Task { await refreshWorktrees(project.id) }
        return project
    }

    func chooseProjects(in folderID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        panel.message = "Choisis un dépôt Git ou un dossier contenant plusieurs dépôts. Ils seront regroupés automatiquement."
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                do { for url in panel.urls { try await self?.addLocation(url, folderID: folderID) } }
                catch { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Importer"
        panel.message = "Les dépôts Git de ce dossier seront ajoutés comme projets sous un dossier virtuel. Les fichiers restent à leur emplacement."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.importFolder(url) }
        }
    }

    func addLocation(_ url: URL, folderID: UUID? = nil) async throws {
        guard !isReadOnly, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let discovery = try await Task.detached(priority: .userInitiated) {
            try RepositoryDiscovery.scan(in: url)
        }.value
        let repositories = discovery.repositories
        if repositories.isEmpty, let warning = discovery.warning {
            throw WorkspaceError(message: warning)
        }
        isImporting = false
        if repositories.isEmpty || (repositories.count == 1 && repositories[0].path == WorkspaceDisk.canonicalPath(url)) {
            _ = try addProject(url, folderID: folderID)
        } else {
            await importFolder(url, discovery: discovery, into: folderID)
        }
    }

    func importFolder(_ url: URL, discovery discovered: RepositoryDiscoveryResult? = nil, into targetFolderID: UUID? = nil) async {
        guard !isReadOnly, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let discovery: RepositoryDiscoveryResult
            if let discovered { discovery = discovered }
            else {
                discovery = try await Task.detached(priority: .userInitiated) {
                    try RepositoryDiscovery.scan(in: url)
                }.value
            }
            let repositories = discovery.repositories
            guard !repositories.isEmpty else {
                throw WorkspaceError(message: discovery.warning ?? "Aucun dépôt Git trouvé dans ce dossier. Choisis le dossier qui contient tes dépôts, ou utilise Ajouter un projet pour un dossier sans Git.")
            }
            let sourcePath = WorkspaceDisk.canonicalPath(url)
            let folderID: UUID
            if let targetFolderID, folders.contains(where: { $0.id == targetFolderID }) {
                folderID = targetFolderID
            } else if let folder = folders.first(where: { $0.sourcePath == sourcePath }) {
                folderID = folder.id
            } else {
                let folder = ProjectFolder(name: url.lastPathComponent, sourcePath: sourcePath)
                folderID = folder.id
                folders.append(folder)
            }
            var addedIDs: [UUID] = []
            for repository in repositories {
                let path = WorkspaceDisk.canonicalPath(repository)
                if let index = projects.firstIndex(where: { $0.path == path }) {
                    projects[index].folderID = folderID
                } else {
                    let project = Project(url: repository, folderID: folderID)
                    projects.append(project)
                    addedIDs.append(project.id)
                }
            }
            revealFolder(folderID)
            if selection == nil {
                selection = projects.first(where: { $0.folderID == folderID })?.worktrees.first?.terminals.first?.id
            }
            save()
            for id in addedIDs { await refreshWorktrees(id) }
            if let warning = discovery.warning {
                errorMessage = "Les dépôts accessibles ont été ajoutés.\n\n" + warning
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func moveProject(_ id: UUID, to folderID: UUID?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].folderID = folderID
        if let folderID { revealFolder(folderID) }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = folders.firstIndex(where: { $0.id == id }) { folders[index].name = name }
        for p in projects.indices {
            if projects[p].id == id { projects[p].name = name }
            for w in projects[p].worktrees.indices {
                for t in projects[p].worktrees[w].terminals.indices where projects[p].worktrees[w].terminals[t].id == id {
                    projects[p].worktrees[w].terminals[t].name = name
                }
            }
        }
        save()
    }

    func removeFolder(_ id: UUID) {
        guard let removed = folders.first(where: { $0.id == id }) else { return }
        let parentID = removed.parentID.flatMap { parent in folders.contains { $0.id == parent } ? parent : nil }
        folders.removeAll { $0.id == id }
        for index in folders.indices where folders[index].parentID == id { folders[index].parentID = parentID }
        for index in projects.indices where projects[index].folderID == id { projects[index].folderID = parentID }
        collapsed.remove(id)
        save()
    }

    func removeProject(_ id: UUID) {
        guard !busyProjects.contains(id), let project = projects.first(where: { $0.id == id }) else { return }
        for terminal in project.worktrees.flatMap(\.terminals) { sessions.close(terminal.id) }
        projects.removeAll { $0.id == id }
        repairSelection()
        save()
    }

    @discardableResult func addTerminal(projectID: UUID, worktreeID: UUID, name: String = "Terminal", command: [String] = [], select: Bool = true) throws -> TerminalContext {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let w = projects[p].worktrees.firstIndex(where: { $0.id == worktreeID }) else {
            throw WorkspaceError(message: "Projet ou worktree introuvable.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminal = TerminalRecord(name: trimmed.isEmpty ? "Terminal" : trimmed)
        projects[p].worktrees[w].terminals.append(terminal)
        reveal(projectID: projectID, worktreeID: worktreeID)
        if select { selection = terminal.id }
        save()
        let context = context(for: terminal.id)!
        sessions.start(context, command: command)
        return context
    }

    func addTerminalInCurrentContext(name: String, command: [String]) throws {
        let current = context(for: selection).map { ($0.project.id, $0.worktree.id) }
        let fallback = projects.lazy.compactMap { project in
            (project.worktrees.first(where: \.isPrimary) ?? project.worktrees.first).map { (project.id, $0.id) }
        }.first
        guard let (projectID, worktreeID) = current ?? fallback else {
            throw WorkspaceError(message: "Ajoute d’abord un projet : la connexion se fait dans un terminal AgentUI.")
        }
        try addTerminal(projectID: projectID, worktreeID: worktreeID, name: name, command: command)
    }

    func closeTerminal(_ id: UUID) {
        let previous = context(for: id)
        sessions.close(id)
        for p in projects.indices {
            for w in projects[p].worktrees.indices {
                projects[p].worktrees[w].terminals.removeAll { $0.id == id }
            }
        }
        if selection == id {
            let project = projects.first { $0.id == previous?.project.id }
            selection = project?.worktrees.first(where: { $0.id == previous?.worktree.id })?.terminals.first?.id
                ?? project?.worktrees.flatMap(\.terminals).first?.id
        }
        save()
    }

    func wakeProject(_ id: UUID) {
        guard !isReadOnly, let project = projects.first(where: { $0.id == id }),
              project.worktrees.allSatisfy({ $0.terminals.isEmpty }),
              let worktree = project.worktrees.first(where: \.isPrimary) ?? project.worktrees.first else { return }
        do { _ = try addTerminal(projectID: id, worktreeID: worktree.id) }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func createWorktree(projectID: UUID, branch: String, command: [String] = [], select: Bool = true) async throws -> TerminalContext {
        guard !busyProjects.contains(projectID) else { throw WorkspaceError(message: "Une opération Git est déjà en cours sur ce projet.") }
        guard let project = projects.first(where: { $0.id == projectID }) else { throw WorkspaceError(message: "Projet introuvable.") }
        busyProjects.insert(projectID)
        defer { busyProjects.remove(projectID) }
        let worktree: Worktree
        do { worktree = try await GitService.createWorktree(project: project, branch: branch) }
        catch let error as WorktreeCreationError {
            let recovered = await Task.detached {
                try? await GitService.existingWorktrees(project: project)
            }.value
            if let index = projects.firstIndex(where: { $0.id == projectID }),
               var partial = recovered?.first(where: { $0.path == error.path }),
               !projects[index].worktrees.contains(where: { $0.path == partial.path }) {
                partial.terminals = []
                projects[index].worktrees.append(partial)
                reveal(projectID: projectID, worktreeID: partial.id)
                save()
            }
            throw error
        }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { throw WorkspaceError(message: "Le projet a été retiré.") }
        projects[index].worktrees.append(worktree)
        reveal(projectID: projectID, worktreeID: worktree.id)
        let terminal = worktree.terminals[0]
        if select { selection = terminal.id }
        save()
        let context = context(for: terminal.id)!
        sessions.start(context, command: command)
        return context
    }

    func deleteWorktree(projectID: UUID, worktreeID: UUID) async throws {
        guard !busyProjects.contains(projectID) else { throw WorkspaceError(message: "Une opération Git est déjà en cours sur ce projet.") }
        guard let project = projects.first(where: { $0.id == projectID }),
              let worktree = project.worktrees.first(where: { $0.id == worktreeID }) else {
            throw WorkspaceError(message: "Worktree introuvable.")
        }
        guard !worktree.isPrimary else { throw WorkspaceError(message: "Le dossier principal du projet ne peut pas être supprimé.") }
        busyProjects.insert(projectID)
        defer { busyProjects.remove(projectID) }
        for terminal in worktree.terminals { sessions.close(terminal.id) }
        try await GitService.removeWorktree(project: project, path: worktree.path)
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].worktrees.removeAll { $0.id == worktreeID }
        if context(for: selection) == nil {
            selection = projects[index].worktrees.flatMap(\.terminals).first?.id
            repairSelection()
        }
        save()
    }

    func refreshWorktrees(_ id: UUID) async {
        guard !busyProjects.contains(id), let project = projects.first(where: { $0.id == id }) else { return }
        guard let discovered = try? await GitService.existingWorktrees(project: project),
              !busyProjects.contains(id),
              let index = projects.firstIndex(where: { $0.id == id }) else { return }
        for worktree in discovered where !projects[index].worktrees.contains(where: { $0.path == worktree.path }) {
            projects[index].worktrees.append(worktree)
        }
        save()
    }

    private func reveal(projectID: UUID, worktreeID: UUID) {
        collapsed.remove(projectID)
        collapsed.remove(worktreeID)
        if let folder = projects.first(where: { $0.id == projectID })?.folderID { revealFolder(folder) }
    }

    private func revealFolder(_ id: UUID) {
        collapsed.remove(id)
        for ancestor in folders.ancestors(of: id) { collapsed.remove(ancestor) }
    }

    private func repairSelection() {
        if context(for: selection) == nil { selection = projects.flatMap(\.worktrees).flatMap(\.terminals).first?.id }
    }

    private func restore(_ snapshot: Workspace) {
        restoring = true
        folders = snapshot.folders
        projects = snapshot.projects
        collapsed = snapshot.collapsed
        selection = snapshot.selection
        restoring = false
    }

    private func save() {
        guard canSave, !restoring else { return }
        revision += 1
        hasUnsavedChanges = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            try? await self?.persistSnapshot()
        }
    }

    func flushPersistence() async throws {
        pendingSave?.cancel()
        pendingSave = nil
        try await persistSnapshot()
    }

    private func persistSnapshot() async throws {
        guard canSave, hasUnsavedChanges else { return }
        let requestedRevision = revision
        let snapshot = state
        do {
            try await writer.write(snapshot, revision: requestedRevision)
            persistedRevision = max(persistedRevision, requestedRevision)
            hasUnsavedChanges = revision > persistedRevision
            if requestedRevision >= failedRevision { persistenceError = nil }
        } catch {
            guard requestedRevision > persistedRevision else { return }
            failedRevision = max(failedRevision, requestedRevision)
            persistenceError = "Modifications non sauvegardées : \(error.localizedDescription)"
            throw WorkspaceError(message: "L’opération a été appliquée en mémoire, mais sa sauvegarde a échoué. Réessaie la sauvegarde dans l’application avant de relancer la commande. \(error.localizedDescription)")
        }
    }
}

import AppKit
import Observation

@MainActor @Observable final class WorkspaceStore {
    private(set) var folders: [ProjectFolder] = []
    private(set) var projects: [Project] = [] {
        didSet { selectedContext = context(for: selection) }
    }
    private var collapsed: Set<UUID> = []
    var selection: UUID? {
        didSet {
            selectedContext = context(for: selection)
            if oldValue != selection { save() }
        }
    }
    private(set) var selectedContext: TerminalContext?
    var state: Workspace { Workspace(folders: folders, projects: projects, selection: selection, collapsed: collapsed) }
    private(set) var persistenceError: String?
    private(set) var hasUnsavedChanges = false
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var persistedRevision: UInt64 = 0
    @ObservationIgnored private var failedRevision: UInt64 = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var restoring = false
    private var removingWorktrees: Set<UUID> = []
    @ObservationIgnored private var recentResumes: [String: (terminal: UUID, at: ContinuousClock.Instant)] = [:]
    @ObservationIgnored private var restoredSessions = false
    private let writer: WorkspaceWriter
    var errorMessage: String?
    var busyProjects: Set<UUID> = []
    private(set) var orphanWorktrees: [DiscoveredWorktree] = []
    @ObservationIgnored private var orphanScan: UInt64 = 0
    private(set) var isImporting = false
    var pendingImport: RepositoryImport?
    @ObservationIgnored private var queuedImports: [RepositoryImport] = []
    let sessions = TerminalSessions()
    private let fileURL: URL
    private var canSave = true

    init(fileURL: URL = WorkspaceDisk.applicationDirectory.appendingPathComponent("workspace.json")) {
        self.fileURL = fileURL
        writer = WorkspaceWriter(fileURL: fileURL)
        do { restore(try WorkspaceDisk.load(from: fileURL)) }
        catch {
            canSave = false
            errorMessage = String(localized: "Couldn’t read the organization. The original file was preserved: \(fileURL.path)\n\(error.localizedDescription)")
        }
        sessions.onAgentsRefreshed = { [weak self] in self?.recordAgentSessions() }
    }

    var isReadOnly: Bool { !canSave }

    func retryLoading() {
        guard isReadOnly else { return }
        do {
            restore(try WorkspaceDisk.load(from: fileURL))
            canSave = true
            errorMessage = nil
            restoreSessions()
        } catch { errorMessage = String(localized: "The organization is still unreadable. The original file is kept: \(fileURL.path)\n\(error.localizedDescription)") }
    }

    var terminalCount: Int { projects.flatMap(\.worktrees).flatMap(\.terminals).count }

    func context(for terminalID: UUID?) -> TerminalContext? {
        TerminalContext(terminalID: terminalID, in: projects)
    }

    func startableContext(for terminalID: UUID) -> TerminalContext? {
        context(for: terminalID).flatMap { removingWorktrees.contains($0.worktree.id) ? nil : $0 }
    }

    func startSession(for terminalID: UUID) {
        guard let context = startableContext(for: terminalID) else { return }
        sessions.start(context)
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
        let canonical = URL(fileURLWithPath: WorkspacePath.canonical(url))
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &directory), directory.boolValue else {
            throw WorkspaceError(message: String(localized: "This folder is no longer accessible: \(canonical.path)"))
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
        Task(priority: .utility) { await refreshWorktrees(project.id) }
        return project
    }

    func chooseProjects(in folderID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose a Git repository or a folder containing several repositories. They’ll be grouped automatically.")
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
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "The Git repositories in this folder will be added as projects under a virtual folder. The files stay where they are.")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.importFolder(url) }
        }
    }

    func addLocation(_ url: URL, folderID: UUID? = nil, review: Bool = true) async throws {
        guard let plan = try await planImport(of: url, into: folderID) else { return }
        if plan.repositoryPaths.isEmpty || plan.repositoryPaths == [WorkspacePath.canonical(url)] {
            _ = try addProject(url, folderID: folderID)
        } else {
            await submit(plan, review: review)
        }
    }

    func importFolder(_ url: URL, into folderID: UUID? = nil, review: Bool = true) async {
        do {
            guard let plan = try await planImport(of: url, into: folderID) else { return }
            guard !plan.repositoryPaths.isEmpty else {
                throw WorkspaceError(message: plan.warning ?? String(localized: "No Git repository found in this folder. Choose the folder that contains your repositories, or use Add Project for a folder without Git."))
            }
            await submit(plan, review: review)
        } catch { errorMessage = error.localizedDescription }
    }

    func showNextImport() {
        guard pendingImport == nil, !queuedImports.isEmpty else { return }
        pendingImport = queuedImports.removeFirst()
    }

    func importRepositories(_ plan: RepositoryImport, keeping paths: Set<String>, flattened: Bool) async {
        guard !isReadOnly, !isImporting, let tree = plan.tree.keeping(paths) else { return }
        isImporting = true
        defer { isImporting = false }
        let filledFolders = Set(folders.map(\.id).filter { !isEmptyFolder($0) })
        let rootID = importRootFolder(for: plan)
        var addedIDs: [UUID] = []
        if flattened {
            for path in tree.repositoryPaths { placeRepository(path, in: rootID, added: &addedIDs) }
        } else {
            place(tree.children ?? [tree], in: rootID, added: &addedIDs)
        }
        removeEmptiedImportFolders(filledFolders)
        revealFolder(rootID)
        if selection == nil {
            let imported = Set(tree.repositoryPaths)
            selection = projects.first(where: { imported.contains($0.path) })?.worktrees.first?.terminals.first?.id
        }
        save()
        for id in addedIDs { await refreshWorktrees(id) }
    }

    private func planImport(of url: URL, into folderID: UUID?) async throws -> RepositoryImport? {
        guard !isReadOnly, !isImporting else { return nil }
        isImporting = true
        defer { isImporting = false }
        let discovery = try await RepositoryDiscovery.scan(in: url)
        if discovery.repositories.isEmpty, let warning = discovery.warning {
            throw WorkspaceError(message: warning)
        }
        return RepositoryImport(source: url, discovery: discovery, target: folders.first { $0.id == folderID })
    }

    private func submit(_ plan: RepositoryImport, review: Bool) async {
        guard review, plan.needsReview else {
            await importRepositories(plan, keeping: Set(plan.repositoryPaths), flattened: false)
            if let warning = plan.warning {
                errorMessage = String(localized: "The accessible repositories were added.") + "\n\n" + warning
            }
            return
        }
        queuedImports.append(plan)
        showNextImport()
    }

    private func importRootFolder(for plan: RepositoryImport) -> UUID {
        if let target = plan.targetFolderID, folders.contains(where: { $0.id == target }) { return target }
        if let folder = folders.first(where: { $0.sourcePath == plan.tree.path }) { return folder.id }
        let folder = ProjectFolder(name: plan.destinationName, sourcePath: plan.tree.path)
        folders.append(folder)
        return folder.id
    }

    private func importedFolder(named name: String, path: String, parentID: UUID) -> UUID {
        guard let index = folders.firstIndex(where: { $0.sourcePath == path }) else {
            let folder = ProjectFolder(name: name, sourcePath: path, parentID: parentID)
            folders.append(folder)
            return folder.id
        }
        let id = folders[index].id
        if canMoveFolder(id, to: parentID) { folders[index].parentID = parentID }
        return id
    }

    private func isEmptyFolder(_ id: UUID) -> Bool {
        !projects.contains { $0.folderID == id } && !folders.contains { $0.parentID == id }
    }

    private func removeEmptiedImportFolders(_ filledFolders: Set<UUID>) {
        while let emptied = folders.first(where: { $0.sourcePath != nil && filledFolders.contains($0.id) && isEmptyFolder($0.id) }) {
            folders.removeAll { $0.id == emptied.id }
            collapsed.remove(emptied.id)
        }
    }

    private func place(_ items: [RepositoryImportItem], in folderID: UUID, added: inout [UUID]) {
        for item in items {
            switch item {
            case .repository(let path, _):
                placeRepository(path, in: folderID, added: &added)
            case .folder(let path, let name, let children):
                let subfolderID = importedFolder(named: name, path: path, parentID: folderID)
                place(children, in: subfolderID, added: &added)
            }
        }
    }

    private func placeRepository(_ path: String, in folderID: UUID, added: inout [UUID]) {
        if let index = projects.firstIndex(where: { $0.path == path }) {
            projects[index].folderID = folderID
        } else {
            let project = Project(url: URL(fileURLWithPath: path), folderID: folderID)
            projects.append(project)
            added.append(project.id)
        }
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
            if let g = projects[p].worktreeGroups.firstIndex(where: { $0.id == id }) { projects[p].worktreeGroups[g].name = name }
            for w in projects[p].worktrees.indices {
                for t in projects[p].worktrees[w].terminals.indices where projects[p].worktrees[w].terminals[t].id == id {
                    projects[p].worktrees[w].terminals[t].name = name
                    projects[p].worktrees[w].terminals[t].hasCustomName = true
                }
            }
        }
        save()
    }

    func applyConversationTitles(_ titles: [UUID: String]) {
        let changed = updateTerminals { terminal in
            guard !terminal.hasCustomName, let title = titles[terminal.id], terminal.name != title else { return false }
            terminal.name = title
            return true
        }
        if changed { save() }
    }

    func recordAgentSessions() { applyAgentResumes(sessions.agentResumes()) }

    func applyAgentResumes(_ resumes: [UUID: AgentResume?]) {
        guard !resumes.isEmpty else { return }
        let changed = updateTerminals { terminal in
            guard let resume = resumes[terminal.id], terminal.resume != resume else { return false }
            terminal.resume = resume
            return true
        }
        if changed { save() }
    }

    func restoreSessions() {
        guard !restoredSessions, !isReadOnly else { return }
        restoredSessions = true
        for project in projects {
            for worktree in project.worktrees {
                for terminal in worktree.terminals where terminal.resume != nil {
                    sessions.start(TerminalContext(project: project, worktree: worktree, terminal: terminal))
                }
            }
        }
    }

    func useAutomaticName(_ terminalID: UUID) {
        updateTerminals { terminal in
            guard terminal.id == terminalID else { return false }
            terminal.hasCustomName = false
            terminal.name = TerminalRecord.defaultName
            return true
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

    func isBusy(_ removal: Removal) -> Bool {
        removal.projectID.map(busyProjects.contains) ?? false
    }

    func remove(_ removal: Removal) {
        guard !isBusy(removal) else {
            errorMessage = String(localized: "A Git operation is in progress on this project. Try again when it’s finished.")
            return
        }
        switch removal {
        case .project(let id): removeProject(id)
        case .terminal(let id): closeTerminal(id)
        case .worktree(let projectID, let worktreeID, _):
            Task {
                do { try await deleteWorktree(projectID: projectID, worktreeID: worktreeID) }
                catch { errorMessage = error.localizedDescription }
            }
        case .orphanWorktree(let path, _): trashOrphanWorktree(at: path)
        }
    }

    @discardableResult func addTerminal(projectID: UUID, worktreeID: UUID, name: String = TerminalRecord.defaultName, command: [String] = [], select: Bool = true) throws -> TerminalContext {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let w = projects[p].worktrees.firstIndex(where: { $0.id == worktreeID }) else {
            throw WorkspaceError(message: String(localized: "Project or worktree not found."))
        }
        guard !removingWorktrees.contains(worktreeID) else { throw WorkspaceError(message: String(localized: "This worktree is being deleted.")) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminal = TerminalRecord(name: trimmed.isEmpty ? TerminalRecord.defaultName : trimmed)
        projects[p].worktrees[w].terminals.append(terminal)
        reveal(projectID: projectID, worktreeID: worktreeID)
        if select { selection = terminal.id }
        save()
        let context = context(for: terminal.id)!
        sessions.start(context, command: command)
        return context
    }

    @discardableResult func resume(_ conversation: AgentConversation, projectID: UUID, worktreeID: UUID, select: Bool = true) throws -> TerminalContext {
        guard let command = conversation.resumeCommand else { throw WorkspaceError(message: String(localized: "Unsupported session ID.")) }
        if let recent = recentResumes[conversation.id], ContinuousClock.now - recent.at < .seconds(30), context(for: recent.terminal) != nil,
           sessions.isRunning(recent.terminal) {
            throw WorkspaceError(message: String(localized: "This conversation was just resumed in another terminal."))
        }
        let context = try addTerminal(projectID: projectID, worktreeID: worktreeID, name: conversation.shortTitle, command: command, select: select)
        recentResumes = recentResumes.filter { ContinuousClock.now - $0.value.at < .seconds(30) }
        recentResumes[conversation.id] = (context.terminal.id, .now)
        return context
    }

    @discardableResult func splitTerminal(_ id: UUID, axis: SplitAxis, command: [String] = []) throws -> TerminalContext {
        guard let current = context(for: id) else { throw WorkspaceError(message: String(localized: "Terminal not found.")) }
        let added = try addTerminal(projectID: current.project.id, worktreeID: current.worktree.id, command: command)
        updateWorktree(current.worktree.id) { worktree in
            if let index = worktree.layouts.firstIndex(where: { $0.contains(id) }) {
                worktree.layouts[index] = worktree.layouts[index].splitting(id, with: added.terminal.id, axis: axis)
            } else {
                worktree.layouts.append(TerminalLayout.terminal(id).splitting(id, with: added.terminal.id, axis: axis))
            }
        }
        save()
        return context(for: added.terminal.id) ?? added
    }

    func layout(for terminalID: UUID) -> TerminalLayout {
        worktree(containing: terminalID)?.layout(containing: terminalID) ?? .terminal(terminalID)
    }

    func worktree(containing terminalID: UUID) -> Worktree? {
        projects.lazy.flatMap(\.worktrees).first { $0.terminals.contains { $0.id == terminalID } }
    }

    func addTerminalInCurrentContext(name: String, command: [String]) throws {
        let current = selectedContext.map { ($0.project.id, $0.worktree.id) }
        let fallback = projects.lazy.compactMap { project in
            (project.worktrees.first(where: \.isPrimary) ?? project.worktrees.first).map { (project.id, $0.id) }
        }.first
        guard let (projectID, worktreeID) = current ?? fallback else {
            throw WorkspaceError(message: String(localized: "Add a project first: sign-in happens in an AgentUI terminal."))
        }
        try addTerminal(projectID: projectID, worktreeID: worktreeID, name: name, command: command)
    }

    func closeTerminal(_ id: UUID) {
        let previous = context(for: id)
        let neighbour = worktree(containing: id)?.layout(containing: id)?.neighbour(of: id)
        sessions.close(id)
        for p in projects.indices {
            for w in projects[p].worktrees.indices {
                projects[p].worktrees[w].terminals.removeAll { $0.id == id }
                projects[p].worktrees[w].layouts = projects[p].worktrees[w].layouts
                    .compactMap { $0.removing(id) }.filter(\.isSplit)
            }
        }
        if selection == id {
            let project = projects.first { $0.id == previous?.project.id }
            selection = neighbour
                ?? project?.worktrees.first(where: { $0.id == previous?.worktree.id })?.terminals.first?.id
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

    @discardableResult func createWorktree(projectID: UUID, branch: String, remote: String? = nil, command: [String] = [], select: Bool = true) async throws -> TerminalContext {
        guard !busyProjects.contains(projectID) else { throw WorkspaceError(message: String(localized: "A Git operation is already in progress on this project.")) }
        guard let project = projects.first(where: { $0.id == projectID }) else { throw WorkspaceError(message: String(localized: "Project not found.")) }
        busyProjects.insert(projectID)
        defer { busyProjects.remove(projectID) }
        let worktree: Worktree
        do { worktree = try await GitService.createWorktree(project: project, branch: branch, remote: remote) }
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
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { throw WorkspaceError(message: String(localized: "The project was removed.")) }
        projects[index].worktrees.append(worktree)
        reveal(projectID: projectID, worktreeID: worktree.id)
        let terminal = worktree.terminals[0]
        if select { selection = terminal.id }
        save()
        let context = context(for: terminal.id)!
        sessions.start(context, command: command)
        return context
    }

    func availableBranches(projectID: UUID) async -> [BranchSuggestion] {
        guard let project = projects.first(where: { $0.id == projectID }) else { return [] }
        return (try? await GitService.availableBranches(project: project)) ?? []
    }

    func fetchRemotes(projectID: UUID) async throws {
        guard !busyProjects.contains(projectID) else { throw WorkspaceError(message: String(localized: "A Git operation is already in progress on this project.")) }
        guard let project = projects.first(where: { $0.id == projectID }) else { throw WorkspaceError(message: String(localized: "Project not found.")) }
        busyProjects.insert(projectID)
        defer { busyProjects.remove(projectID) }
        try await GitService.fetchRemotes(project: project)
    }

    func deleteWorktree(projectID: UUID, worktreeID: UUID) async throws {
        guard !busyProjects.contains(projectID) else { throw WorkspaceError(message: String(localized: "A Git operation is already in progress on this project.")) }
        guard let project = projects.first(where: { $0.id == projectID }),
              let worktree = project.worktrees.first(where: { $0.id == worktreeID }) else {
            throw WorkspaceError(message: String(localized: "Worktree not found."))
        }
        guard !worktree.isPrimary else { throw WorkspaceError(message: String(localized: "The project’s main folder can’t be deleted.")) }
        busyProjects.insert(projectID)
        removingWorktrees.insert(worktreeID)
        defer {
            busyProjects.remove(projectID)
            removingWorktrees.remove(worktreeID)
        }
        let started = worktree.terminals.filter { sessions.isRunning($0.id) }
        for terminal in started { sessions.close(terminal.id) }
        do {
            try await GitService.removeWorktree(project: project, path: worktree.path)
        } catch {
            for context in started.compactMap({ context(for: $0.id) }) { sessions.start(context) }
            throw error
        }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let remaining = projects[index].worktrees.first { $0.id == worktreeID }?.terminals ?? []
        for terminal in remaining { sessions.close(terminal.id) }
        projects[index].worktrees.removeAll { $0.id == worktreeID }
        if selectedContext == nil {
            selection = projects[index].worktrees.flatMap(\.terminals).first?.id
            repairSelection()
        }
        save()
    }

    @discardableResult func addWorktreeGroup(_ name: String, projectID: UUID, moving worktreeID: UUID? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let group = WorktreeGroup(name: name)
        projects[index].worktreeGroups.append(group)
        if let worktreeID { moveWorktree(worktreeID, to: group.id) }
        collapsed.remove(group.id)
        save()
        return group.id
    }

    @discardableResult func moveWorktree(_ worktreeID: UUID, to groupID: UUID?) -> Bool {
        guard let project = projects.first(where: { $0.worktrees.contains { $0.id == worktreeID && !$0.isPrimary } }),
              groupID == nil || project.worktreeGroups.contains(where: { $0.id == groupID }) else { return false }
        updateWorktree(worktreeID) { $0.groupID = groupID }
        if let groupID { collapsed.remove(groupID) }
        save()
        return true
    }

    func removeWorktreeGroup(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.worktreeGroups.contains { $0.id == id } }) else { return }
        projects[index].worktreeGroups.removeAll { $0.id == id }
        for w in projects[index].worktrees.indices where projects[index].worktrees[w].groupID == id {
            projects[index].worktrees[w].groupID = nil
        }
        collapsed.remove(id)
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

    func adoptWorktrees(in directories: [URL]) async {
        orphanScan += 1
        let scan = orphanScan
        let discovered = await WorktreeFolder.scan(directories)
        guard scan == orphanScan else { return }
        let unknown = discovered.filter { !isKnownWorktree($0.path) }
        let owners = Set(unknown.compactMap { worktree in projects.first { $0.path == worktree.repositoryPath }?.id })
        for id in owners { await refreshWorktrees(id) }
        guard scan == orphanScan else { return }
        let orphans = unknown.filter { !isKnownWorktree($0.path) && !belongsToBusyProject($0) }
        if orphanWorktrees != orphans { orphanWorktrees = orphans }
    }

    func addRepository(of orphan: DiscoveredWorktree) {
        guard let repositoryPath = orphan.repositoryPath else { return }
        do { try addProject(URL(fileURLWithPath: repositoryPath)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func trashOrphanWorktree(at path: String) {
        guard let orphan = orphanWorktrees.first(where: { $0.path == path }) else { return }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: orphan.path), resultingItemURL: nil)
            orphanScan += 1
            orphanWorktrees.removeAll { $0.path == orphan.path }
            if orphan.hasRepository, let repositoryPath = orphan.repositoryPath {
                Task { _ = try? await GitService.run(["worktree", "prune"], at: repositoryPath, timeout: 10) }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func isKnownWorktree(_ path: String) -> Bool {
        projects.contains { $0.worktrees.contains { $0.path == path } }
    }

    private func belongsToBusyProject(_ worktree: DiscoveredWorktree) -> Bool {
        busyProjects.contains { id in projects.first { $0.id == id }?.path == worktree.repositoryPath }
    }

    @discardableResult private func updateTerminals(_ update: (inout TerminalRecord) -> Bool) -> Bool {
        var changed = false
        for p in projects.indices {
            for w in projects[p].worktrees.indices {
                for t in projects[p].worktrees[w].terminals.indices {
                    var terminal = projects[p].worktrees[w].terminals[t]
                    guard update(&terminal) else { continue }
                    projects[p].worktrees[w].terminals[t] = terminal
                    changed = true
                }
            }
        }
        return changed
    }

    private func updateWorktree(_ id: UUID, _ update: (inout Worktree) -> Void) {
        for p in projects.indices {
            if let w = projects[p].worktrees.firstIndex(where: { $0.id == id }) { update(&projects[p].worktrees[w]) }
        }
    }

    private func reveal(projectID: UUID, worktreeID: UUID) {
        collapsed.remove(projectID)
        collapsed.remove(worktreeID)
        if let groupID = projects.first(where: { $0.id == projectID })?.worktrees.first(where: { $0.id == worktreeID })?.groupID {
            collapsed.remove(groupID)
        }
        if let folder = projects.first(where: { $0.id == projectID })?.folderID { revealFolder(folder) }
    }

    private func revealFolder(_ id: UUID) {
        collapsed.remove(id)
        for ancestor in folders.ancestors(of: id) { collapsed.remove(ancestor) }
    }

    private func repairSelection() {
        if selectedContext == nil { selection = projects.flatMap(\.worktrees).flatMap(\.terminals).first?.id }
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
            persistenceError = String(localized: "Unsaved changes: \(error.localizedDescription)")
            throw WorkspaceError(message: String(localized: "The operation was applied in memory, but saving it failed. Retry saving in the app before running the command again. \(error.localizedDescription)"))
        }
    }
}

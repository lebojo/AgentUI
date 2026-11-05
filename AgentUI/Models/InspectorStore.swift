import Foundation
import Observation

@MainActor @Observable final class InspectorStore {
    private enum RemoteTrigger: Sendable {
        case changed, periodic
    }

    var comparisonBase: ComparisonBranch?
    private(set) var actions: GitActionQueue?
    private(set) var local: LocalGitSnapshot?
    private(set) var changeTrees = GitChangeTrees()
    private(set) var remote: RemoteSnapshot?
    private(set) var localLoading = false
    private(set) var remoteLoading = false
    var loading: Bool { localLoading || remoteLoading }
    private(set) var lacksChangeRequest = false
    private(set) var localError: String?
    private(set) var remoteError: String?
    @ObservationIgnored private let actionQueues: GitActionQueues
    @ObservationIgnored private var path: String?
    @ObservationIgnored private var reloadTrigger: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var remoteKey: String?
    @ObservationIgnored private var remoteDate: ContinuousClock.Instant?
    @ObservationIgnored private var remoteInterval: Duration = .seconds(60)
    @ObservationIgnored private var showsNextLocalLoad = true

    typealias LocalQuery = @Sendable (String) async throws -> LocalGitSnapshot
    typealias RemoteQuery = @Sendable (LocalGitSnapshot) async throws -> RemoteSnapshot
    typealias GitCommand = (GitAction, String) async throws -> Void

    init(actionQueues: GitActionQueues = GitActionQueues()) {
        self.actionQueues = actionQueues
    }

    var commitTitle: String {
        get { actions?.commitTitle ?? "" }
        set { actions?.commitTitle = newValue }
    }

    var commitMessage: String {
        get { actions?.commitMessage ?? "" }
        set { actions?.commitMessage = newValue }
    }

    var pendingAction: GitAction? { actions?.pendingAction }

    var actionFailure: GitActionFailure? {
        get { actions?.failure }
        set { actions?.failure = newValue }
    }

    private var currentKey: String? {
        branchKey.map { $0 + "|" + (local?.headSHA ?? "") }
    }

    private var branchKey: String? {
        local.map { $0.root + "|" + ($0.branch?.name ?? "") }
    }

    private var remoteIsStale: Bool {
        remoteDate.map { $0.duration(to: .now) >= remoteInterval } ?? true
    }

    func monitor(path: String, forceRemote: Bool = false, changes: AsyncStream<Void>, remoteInterval: Duration = .seconds(60),
                 readLocal: @escaping LocalQuery, readRemote: @escaping RemoteQuery) async {
        let token = UUID()
        generation = token
        self.remoteInterval = remoteInterval
        if self.path != path {
            self.path = path
            local = nil; remote = nil; localError = nil; remoteError = nil
            changeTrees = GitChangeTrees()
            remoteKey = nil; remoteDate = nil
            lacksChangeRequest = false; comparisonBase = nil
        }
        localLoading = false; remoteLoading = false
        showsNextLocalLoad = true
        if forceRemote { remoteKey = nil }
        let (triggers, trigger) = AsyncStream.makeStream(of: RemoteTrigger.self, bufferingPolicy: .bufferingNewest(1))
        let (reloads, reload) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        reloadTrigger = reload
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in changes { reload.yield() }
                reload.finish()
            }
            group.addTask { await self.localLoop(path: path, token: token, changes: reloads, trigger: trigger, readLocal: readLocal) }
            group.addTask { await self.remoteLoop(token: token, triggers: triggers, readRemote: readRemote) }
            group.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: remoteInterval) } catch { return }
                    trigger.yield(.periodic)
                }
            }
        }
        trigger.finish()
        reload.finish()
        if generation == token { localLoading = false; remoteLoading = false; reloadTrigger = nil }
    }

    func reload(remote: Bool = false) {
        if remote { remoteKey = nil }
        reloadTrigger?.yield()
    }

    @discardableResult func perform(_ action: GitAction, at root: String, run: @escaping GitCommand) async -> Bool {
        let queue = actionQueues.queue(at: root)
        actions = queue
        let succeeded = await queue.perform(action) { try await run(action, root) }
        reload(remote: action.updatesRemote)
        return succeeded
    }

    func cancelActions() {
        actions?.cancel()
    }

    private func localLoop(path: String, token: UUID, changes: AsyncStream<Void>,
                           trigger: AsyncStream<RemoteTrigger>.Continuation, readLocal: LocalQuery) async {
        for await _ in changes {
            guard !Task.isCancelled, generation == token else { break }
            if showsNextLocalLoad || local == nil { localLoading = true }
            showsNextLocalLoad = false
            do {
                let snapshot = try await readLocal(path)
                let trees = snapshot.changes == local?.changes ? changeTrees : await GitChangeTrees.build(snapshot)
                guard !Task.isCancelled, generation == token else { break }
                let oldKey = currentKey, oldBranchKey = branchKey
                actions = actionQueues.queue(at: snapshot.root)
                local = snapshot
                changeTrees = trees
                localError = nil
                if currentKey != oldKey { remote = nil; remoteError = nil; remoteDate = nil }
                if branchKey != oldBranchKey { lacksChangeRequest = false }
                if currentKey != remoteKey || remoteIsStale { trigger.yield(.changed) }
            } catch is CancellationError { break }
            catch {
                guard generation == token, !Task.isCancelled else { break }
                local = nil; remote = nil; remoteError = nil
                changeTrees = GitChangeTrees()
                remoteKey = nil; remoteDate = nil
                lacksChangeRequest = false
                localError = error.localizedDescription
            }
            if localLoading { localLoading = false }
        }
        if generation == token { localLoading = false }
    }

    private func remoteLoop(token: UUID, triggers: AsyncStream<RemoteTrigger>, readRemote: RemoteQuery) async {
        for await reason in triggers {
            guard !Task.isCancelled, generation == token else { break }
            guard let snapshot = local, let key = currentKey,
                  reason == .periodic || key != remoteKey || remoteIsStale else { continue }
            if key != remoteKey { remoteLoading = true }
            do {
                let result = try await readRemote(snapshot)
                guard !Task.isCancelled, generation == token else { break }
                if currentKey == key {
                    remote = result; remoteError = nil
                    remoteKey = key; remoteDate = .now
                    lacksChangeRequest = result.changeRequest == nil
                }
            } catch is CancellationError { break }
            catch {
                guard generation == token, !Task.isCancelled else { break }
                if currentKey == key {
                    remote = nil; remoteError = error.localizedDescription
                    remoteKey = key; remoteDate = .now
                    lacksChangeRequest = true
                }
            }
            if remoteLoading { remoteLoading = false }
        }
        if generation == token { remoteLoading = false }
    }
}

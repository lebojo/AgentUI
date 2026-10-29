import Foundation
import Observation

@MainActor @Observable final class InspectorStore {
    private enum RemoteTrigger: Sendable {
        case changed, periodic
    }

    private(set) var local: LocalGitSnapshot?
    private(set) var github: GitHubSnapshot?
    private(set) var localLoading = false
    private(set) var remoteLoading = false
    var loading: Bool { localLoading || remoteLoading }
    private(set) var localError: String?
    private(set) var githubError: String?
    @ObservationIgnored private var path: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var remoteKey: String?
    @ObservationIgnored private var remoteDate: ContinuousClock.Instant?
    @ObservationIgnored private var remoteInterval: Duration = .seconds(60)

    typealias LocalQuery = @Sendable (String) async throws -> LocalGitSnapshot
    typealias RemoteQuery = @Sendable (LocalGitSnapshot) async throws -> GitHubSnapshot
    @ObservationIgnored private let readLocal: LocalQuery
    @ObservationIgnored private let readRemote: RemoteQuery

    init(readLocal: @escaping LocalQuery = { try await InspectorService.localGit(at: $0) },
         readRemote: @escaping RemoteQuery = { try await InspectorService.github(at: $0.root, branch: $0.branch, headSHA: $0.headSHA) }) {
        self.readLocal = readLocal
        self.readRemote = readRemote
    }

    private var currentKey: String? {
        local.map { $0.root + "|" + ($0.branch?.name ?? "") + "|" + ($0.headSHA ?? "") }
    }

    private var remoteIsStale: Bool {
        remoteDate.map { $0.duration(to: .now) >= remoteInterval } ?? true
    }

    func monitor(path: String, forceRemote: Bool = false, changes: AsyncStream<Void>,
                 remoteInterval: Duration = .seconds(60)) async {
        let token = UUID()
        generation = token
        self.remoteInterval = remoteInterval
        if self.path != path {
            self.path = path
            local = nil; github = nil; localError = nil; githubError = nil
            remoteKey = nil; remoteDate = nil
        }
        localLoading = false; remoteLoading = false
        if forceRemote { remoteKey = nil }
        let (triggers, trigger) = AsyncStream.makeStream(of: RemoteTrigger.self, bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.localLoop(path: path, token: token, changes: changes, trigger: trigger) }
            group.addTask { await self.remoteLoop(token: token, triggers: triggers) }
            group.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: remoteInterval) } catch { return }
                    trigger.yield(.periodic)
                }
            }
        }
        trigger.finish()
        if generation == token { localLoading = false; remoteLoading = false }
    }

    private func localLoop(path: String, token: UUID, changes: AsyncStream<Void>,
                           trigger: AsyncStream<RemoteTrigger>.Continuation) async {
        for await _ in changes {
            guard !Task.isCancelled, generation == token else { break }
            localLoading = true
            do {
                let snapshot = try await readLocal(path)
                guard !Task.isCancelled, generation == token else { break }
                let oldKey = currentKey
                local = snapshot
                localError = nil
                if currentKey != oldKey { github = nil; githubError = nil }
                if currentKey != remoteKey || remoteIsStale { trigger.yield(.changed) }
            } catch is CancellationError { break }
            catch {
                guard generation == token, !Task.isCancelled else { break }
                local = nil; github = nil; githubError = nil
                remoteKey = nil; remoteDate = nil
                localError = error.localizedDescription
            }
            localLoading = false
        }
        if generation == token { localLoading = false }
    }

    private func remoteLoop(token: UUID, triggers: AsyncStream<RemoteTrigger>) async {
        for await reason in triggers {
            guard !Task.isCancelled, generation == token else { break }
            guard let snapshot = local, let key = currentKey,
                  reason == .periodic || key != remoteKey || remoteIsStale else { continue }
            remoteLoading = true
            do {
                let result = try await readRemote(snapshot)
                guard !Task.isCancelled, generation == token else { break }
                if currentKey == key {
                    github = result; githubError = nil
                    remoteKey = key; remoteDate = .now
                }
            } catch is CancellationError { break }
            catch {
                guard generation == token, !Task.isCancelled else { break }
                if currentKey == key {
                    github = nil; githubError = error.localizedDescription
                    remoteKey = key; remoteDate = .now
                }
            }
            remoteLoading = false
        }
        if generation == token { remoteLoading = false }
    }
}

import Foundation
import Observation

@MainActor @Observable final class InspectorStore {
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
    @ObservationIgnored private var remoteDate: Date?

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

    /// Both loops are structured children: hiding the inspector cancels queries immediately.
    /// Local polling never awaits GitHub, even when the network stalls.
    func monitor(path: String, forceRemote: Bool = false,
                 localInterval: Duration = .seconds(5), remoteInterval: Duration = .seconds(1)) async {
        let token = UUID()
        generation = token
        if self.path != path {
            self.path = path
            local = nil; github = nil; localError = nil; githubError = nil
            remoteKey = nil; remoteDate = nil
        }
        localLoading = false; remoteLoading = false
        if forceRemote { remoteDate = nil }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.localLoop(path: path, token: token, interval: localInterval) }
            group.addTask { await self.remoteLoop(token: token, interval: remoteInterval) }
        }
    }

    private func localLoop(path: String, token: UUID, interval: Duration) async {
        while !Task.isCancelled, generation == token {
            localLoading = true
            do {
                let snapshot = try await readLocal(path)
                guard !Task.isCancelled, generation == token else { break }
                let oldKey = currentKey
                local = snapshot
                localError = nil
                if currentKey != oldKey { github = nil; githubError = nil; remoteDate = nil }
            } catch is CancellationError { break }
            catch {
                guard generation == token, !Task.isCancelled else { break }
                local = nil; github = nil; githubError = nil
                remoteKey = nil; remoteDate = nil
                localError = error.localizedDescription
            }
            localLoading = false
            do { try await Task.sleep(for: interval) } catch { break }
        }
        if generation == token { localLoading = false }
    }

    private func remoteLoop(token: UUID, interval: Duration) async {
        while !Task.isCancelled, generation == token {
            if let snapshot = local, let key = currentKey,
               key != remoteKey || Date().timeIntervalSince(remoteDate ?? .distantPast) >= 60 {
                remoteLoading = true
                do {
                    let result = try await readRemote(snapshot)
                    guard !Task.isCancelled, generation == token else { break }
                    // A branch/HEAD change while gh was running must never publish stale checks.
                    if currentKey == key {
                        github = result; githubError = nil
                        remoteKey = key; remoteDate = Date()
                    }
                } catch is CancellationError { break }
                catch {
                    guard generation == token, !Task.isCancelled else { break }
                    if currentKey == key {
                        github = nil; githubError = error.localizedDescription
                        remoteKey = key; remoteDate = Date()
                    }
                }
                remoteLoading = false
            }
            do { try await Task.sleep(for: interval) } catch { break }
        }
        if generation == token { remoteLoading = false }
    }
}

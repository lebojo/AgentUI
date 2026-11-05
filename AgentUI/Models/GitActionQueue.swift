import Foundation
import Observation

@MainActor @Observable final class GitActionQueue {
    typealias Command = () async throws -> Void

    var commitTitle = ""
    var commitMessage = ""
    var failure: GitActionFailure?
    private(set) var pendingAction: GitAction?
    @ObservationIgnored private var waiting: [CheckedContinuation<Bool, Never>] = []
    @ObservationIgnored private var running: Task<Void, any Error>?
    @ObservationIgnored private var generation = 0

    var isIdle: Bool { pendingAction == nil && commitTitle.isEmpty && commitMessage.isEmpty && failure == nil }

    func perform(_ action: GitAction, run: @escaping Command) async -> Bool {
        let generation = generation
        if pendingAction != nil {
            let admitted = await withCheckedContinuation { waiting.append($0) }
            guard admitted else { return false }
        }
        defer { handOff() }
        guard !Task.isCancelled, generation == self.generation else { return false }
        pendingAction = action
        let task = Task { try await run() }
        running = task
        defer { running = nil }
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            if let failure, action.retries(failure.action) { self.failure = nil }
            return true
        } catch is CancellationError {
            return false
        } catch {
            failure = GitActionFailure(action: action, error: error.localizedDescription)
            return false
        }
    }

    func cancel() {
        generation += 1
        let dropped = waiting
        waiting = []
        dropped.forEach { $0.resume(returning: false) }
        running?.cancel()
    }

    private func handOff() {
        if waiting.isEmpty { pendingAction = nil } else { waiting.removeFirst().resume(returning: true) }
    }
}

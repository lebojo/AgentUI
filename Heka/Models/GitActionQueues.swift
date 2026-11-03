import Foundation

@MainActor final class GitActionQueues {
    private var queues: [String: GitActionQueue] = [:]

    var hasPendingAction: Bool { queues.values.contains { $0.pendingAction != nil } }

    func queue(at root: String) -> GitActionQueue {
        if let queue = queues[root] { return queue }
        let queue = GitActionQueue()
        queues[root] = queue
        return queue
    }

    func prune(keepingRootsOf worktreePaths: [String]) {
        queues = queues.filter { root, queue in
            !queue.isIdle || worktreePaths.contains { $0 == root || $0.hasPrefix(root + "/") }
        }
    }
}

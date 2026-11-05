import Foundation

@MainActor final class GitActionQueues {
    private var queues: [String: GitActionQueue] = [:]

    func queue(at root: String) -> GitActionQueue {
        if let queue = queues[root] { return queue }
        let queue = GitActionQueue()
        queues[root] = queue
        return queue
    }
}

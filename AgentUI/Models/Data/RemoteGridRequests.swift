import Foundation

struct RemoteGridRequests: Equatable, Sendable {
    private struct Request: Equatable, Sendable {
        let viewer: UUID
        let size: TerminalGridSize
    }

    private var requests: [Request] = []
    private var isTakenBack = false

    var size: TerminalGridSize? { isTakenBack ? nil : requests.last?.size }
    var isEmpty: Bool { requests.isEmpty && !isTakenBack }

    mutating func request(_ size: TerminalGridSize, by viewer: UUID) {
        requests.removeAll { $0.viewer == viewer }
        requests.append(Request(viewer: viewer, size: size))
    }

    mutating func withdraw(_ viewer: UUID) {
        requests.removeAll { $0.viewer == viewer }
    }

    mutating func takeBack() {
        if !requests.isEmpty { isTakenBack = true }
    }

    mutating func receive(_ input: some Collection<UInt8>, from viewer: UUID) {
        guard !input.isTerminalFocusReport, let index = requests.firstIndex(where: { $0.viewer == viewer }) else { return }
        isTakenBack = false
        requests.append(requests.remove(at: index))
    }
}

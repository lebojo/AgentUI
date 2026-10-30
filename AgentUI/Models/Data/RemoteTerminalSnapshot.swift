import Foundation

struct RemoteTerminalSnapshot: Codable, Sendable {
    let identity: UUID
    let isChat: Bool
    let output: Data
    let reset: Bool
    let columns: Int
    let rows: Int
    let transcript: [SessionMessage]
    let transcriptDropped: Int
    let transcriptStart: Int
    let transcriptAppend: SessionTextAppend?
    let hasExited: Bool
    let exitCode: Int32?
    var chatSource: SessionChatSource = .terminal
}


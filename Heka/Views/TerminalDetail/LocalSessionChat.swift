import SwiftUI

struct LocalSessionChat: View {
    let session: TerminalSession

    var body: some View {
        SessionChatView(messages: session.transcript.messages, source: session.transcript.source, isEnabled: !session.hasExited) { text in
            try await session.send(Data((text + "\r").utf8), message: text, from: .local)
        } control: { data in
            try await session.send(data, from: .local)
        }
        .task(id: session.identity) {
            session.acquireChat()
            await Task.waitUntilCancelled()
            session.releaseChat()
        }
    }
}

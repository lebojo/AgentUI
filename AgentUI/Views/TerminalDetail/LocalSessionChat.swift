import SwiftUI

struct LocalSessionChat: View {
    let session: TerminalSession

    var body: some View {
        SessionChatView(messages: session.transcript.messages, source: session.transcript.source, isEnabled: !session.hasExited) { text in
            session.usedLocally()
            try await session.send(Data((text + "\r").utf8), message: text)
        } control: { data in
            session.usedLocally()
            try await session.send(data)
        }
        .task(id: session.identity) {
            session.acquireChat()
            await Task.waitUntilCancelled()
            session.releaseChat()
        }
    }
}

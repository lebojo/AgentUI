import SwiftUI
import Observation

struct LocalSessionChat: View {
    let session: TerminalSession

    var body: some View {
        SessionChatView(messages: session.transcript.messages, source: session.transcript.source, isEnabled: !session.hasExited) { text in
            try await session.send(Data((text + "\r").utf8), message: text)
        } control: { data in
            try await session.send(data)
        }
        .task(id: session.identity) {
            session.acquireChat()
            defer { session.releaseChat() }
            // One invalidation signal, coalesced before rendering; no idle timer or per-byte view updates.
            let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            continuation.yield(())
            for await _ in changes {
                if Task.isCancelled { break }
                withObservationTracking { _ = session.outputRevision; _ = session.transcript.source } onChange: { continuation.yield(()) }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                session.updateTranscript()
            }
            continuation.finish()
        }
    }
}

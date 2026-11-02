import SwiftUI

struct SubagentTranscript: View {
    @State private var transcript = SessionTranscript()

    let journal: URL

    var body: some View {
        Group {
            if transcript.source == .terminal {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SessionTranscriptList(messages: transcript.messages, source: transcript.source)
            }
        }
        .background(Palette.surface)
        .task(id: journal) {
            let monitor = AgentJournalMonitor(transcript: transcript)
            monitor.attach(AgentJournal(source: .claude, url: journal, isSubagent: true))
            await Task.waitUntilCancelled()
            monitor.attach(nil)
        }
    }
}

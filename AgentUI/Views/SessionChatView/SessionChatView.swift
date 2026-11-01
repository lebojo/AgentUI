import SwiftUI

struct SessionChatView: View {
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?

    let messages: [SessionMessage]
    let source: SessionChatSource
    let isEnabled: Bool
    let send: (String) async throws -> Void
    let control: (Data) async throws -> Void

    var body: some View {
        SessionTranscriptList(messages: messages, source: source)
        .background(Palette.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SessionComposer(draft: $draft, source: source, sending: sending, isEnabled: isEnabled,
                            submit: submit, control: sendControl)
        }
        .alert("Envoi impossible", isPresented: $error.isPresent) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func submit() {
        guard !sending, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = draft
        sending = true
        Task {
            defer { sending = false }
            do {
                try await send(text)
                if draft == text { draft = "" }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func sendControl(_ data: Data) {
        Task {
            do { try await control(data) }
            catch { self.error = error.localizedDescription }
        }
    }
}


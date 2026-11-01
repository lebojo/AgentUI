import SwiftUI

struct SessionMessageRow: View, Equatable {
    let message: SessionMessage
    let agent: ConversationAgent?

    private var author: String {
        switch message.kind {
        case .input: "Vous"
        case .assistant: agent?.title ?? "Agent"
        case .output, .tool, .notice: "Sortie de la session"
        }
    }

    var body: some View {
        if message.kind == .tool {
            DisclosureGroup {
                Text(verbatim: message.text).font(Typography.code).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Spacing.s)
            } label: {
                Label(message.title ?? "Outil", systemImage: message.toolState == .failed ? "exclamationmark.circle" : (message.toolState == .completed ? "checkmark.circle" : "gearshape"))
                    .font(Typography.caption).foregroundStyle(message.toolState == .failed ? Palette.danger : Palette.textSecondary)
            }.padding(Spacing.l).background(Palette.fill.opacity(0.3), in: RoundedRectangle(cornerRadius: Radius.m))
        } else {
            HStack {
                if message.kind == .input { Spacer(minLength: Spacing.xl) }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(author)
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    if message.kind == .assistant {
                        SessionMarkdown(text: message.text)
                    } else {
                        Text(verbatim: message.text.isEmpty ? "…" : message.text)
                            .font(message.kind == .input ? Typography.body : Typography.chatOutput).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.l)
                .background(message.kind == .input ? Palette.accent.opacity(0.12) : Palette.fill.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: Radius.m))
                if message.kind != .input { Spacer(minLength: Spacing.s) }
            }
        }
    }
}

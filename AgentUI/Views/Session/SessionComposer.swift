import SwiftUI

struct SessionComposer: View {
    @Binding var draft: String

    let source: SessionChatSource
    let sending: Bool
    let isEnabled: Bool
    let submit: () -> Void
    let control: (Data) -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                if source == .terminal {
                    Button("Échap") { control(Data([27])) }
                }
                Button("Interrompre") { control(Data([source.interruptKey])) }
                if source == .terminal {
                    Button("Entrée") { control(Data([13])) }
                }
                Spacer()
            }
            .font(Typography.caption)
            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
            HStack(alignment: .bottom) {
                TextField(source.agent.map { "Message à \($0.title)" } ?? "Message ou commande", text: $draft, axis: .vertical)
                    .autocorrectionDisabled()
                    .commandInputTraits()
                    .lineLimit(1...6).textFieldStyle(.plain)
                    .onSubmit(submit)
                    .padding(Spacing.m)
                    .background(Palette.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.m))
                Button(action: submit) {
                    Group {
                        if sending { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Envoyer à la session")
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
        .background(Palette.bar)
        .disabled(!isEnabled)
    }
}

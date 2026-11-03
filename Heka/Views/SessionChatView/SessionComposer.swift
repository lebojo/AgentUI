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
                    Button("Ctrl-C") { control(Data([3])) }
                }
                Button("Interrupt") { control(Data([27])) }
                if source == .terminal {
                    Button("Return") { control(Data([13])) }
                }
                Spacer()
            }
            .font(Typography.caption)
            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
            HStack(alignment: .bottom) {
                TextField(source.agent.map { "Message \($0.title)" } ?? "Message or command", text: $draft, axis: .vertical)
                    .autocorrectionDisabled()
                    .commandInputTraits()
                    .lineLimit(1...6).textFieldStyle(.plain)
                    .submitsOnReturn($draft, perform: submit)
                    .padding(Spacing.m)
                    .background(Palette.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.m))
                Button(action: submit) {
                    Group {
                        if sending { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.up.circle.fill").font(Typography.sendSymbol) }
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send to Session")
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
        .background(Palette.bar)
        .disabled(!isEnabled)
    }
}

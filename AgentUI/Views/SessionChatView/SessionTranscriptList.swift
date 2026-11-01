import SwiftUI

struct SessionTranscriptList: View {
    @State private var followsLatest = true
    @State private var lastContentOrigin: CGFloat?

    let messages: [SessionMessage]
    let source: SessionChatSource

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.l) {
                        if messages.isEmpty {
                            ContentUnavailableView(source.agent.map { "Conversation \($0.title)" } ?? "La session est prête",
                                                   systemImage: "bubble.left.and.bubble.right",
                                                   description: Text(source.agent == nil ? "Écris pour continuer le travail sur le Mac." : "Les messages de cette session apparaîtront ici. Les menus interactifs sont accessibles dans Terminal."))
                        }
                        ForEach(messages) { message in SessionMessageRow(message: message, agent: source.agent).equatable() }
                        if source.agent != nil, messages.last?.kind == .input {
                            HStack { ProgressView().controlSize(.small); Text("En attente d’une réponse…").font(Typography.caption) }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding()
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: TranscriptFrame.self, value: geometry.frame(in: .named("transcript")))
                    })
                }
                .coordinateSpace(name: "transcript")
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(TranscriptFrame.self) { frame in
                    guard let frame else { return }
                    if lastContentOrigin == nil || abs((lastContentOrigin ?? 0) - frame.minY) > 0.5 {
                        followsLatest = frame.maxY <= viewport.size.height + 60
                    }
                    lastContentOrigin = frame.minY
                }
                .onChange(of: messages) { old, _ in
                    if old.isEmpty || followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: viewport.size.height) { if followsLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button { followsLatest = true; proxy.scrollTo("latest", anchor: .bottom) } label: {
                            Label("Derniers messages", systemImage: "arrow.down")
                        }.buttonStyle(.borderedProminent).font(Typography.caption).padding()
                    }
                }
            }
        }
    }
}

private struct TranscriptFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() }
}

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
                            ContentUnavailableView(source.agent.map { "\($0.title) Conversation" } ?? "The Session Is Ready",
                                                   systemImage: "bubble.left.and.bubble.right",
                                                   description: Text(source.agent == nil ? "Write to continue working on the Mac." : "Messages from this session will appear here. Interactive menus are available in Terminal."))
                        }
                        ForEach(messages) { message in SessionMessageRow(message: message, agent: source.agent).equatable() }
                        if source.agent != nil, messages.last?.kind == .input {
                            HStack { ProgressView().controlSize(.small); Text("Waiting for a response…").font(Typography.caption) }
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
                            Label("Latest Messages", systemImage: "arrow.down")
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

import SwiftUI

struct FloatingTerminalCommands: Commands {
    let floating: FloatingTerminalStore

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Floating Terminal") { floating.isPresented.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
        }
    }
}

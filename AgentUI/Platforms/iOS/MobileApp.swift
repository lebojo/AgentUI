import SwiftUI

@main struct MobileApp: App {
    @State private var store = MobileWorkspaceStore()

    var body: some Scene {
        WindowGroup { MobileWorkspaceView(store: store) }
    }
}

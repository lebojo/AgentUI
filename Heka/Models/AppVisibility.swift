import AppKit
import Observation

@MainActor @Observable final class AppVisibility {
    private(set) var isVisible = true
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeOcclusionStateNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        isVisible = NSApp.occlusionState.contains(.visible)
    }
}

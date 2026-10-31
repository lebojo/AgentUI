import Foundation

enum FileWatch {
    static func make(_ url: URL, events: DispatchSource.FileSystemEvent,
                     changed: @escaping @MainActor @Sendable (DispatchSource.FileSystemEvent) -> Void) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak source] in
            let event = source?.data ?? []
            MainActor.assumeIsolated { changed(event) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}

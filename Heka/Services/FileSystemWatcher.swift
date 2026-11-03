import Foundation
import Darwin

final class FileSystemWatcher: Sendable {
    private let source: DispatchSourceFileSystemObject

    init(_ url: URL, events: DispatchSource.FileSystemEvent = [.write, .delete, .rename], queue: DispatchQueue,
         onChange: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void) throws {
        let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak source] in onChange(source?.data ?? []) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func cancel() { source.cancel() }
}

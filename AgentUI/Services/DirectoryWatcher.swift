import Foundation
import Darwin

final class DirectoryWatcher: Sendable {
    private let source: DispatchSourceFileSystemObject

    init(_ directory: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) throws {
        let descriptor = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    func cancel() { source.cancel() }
}

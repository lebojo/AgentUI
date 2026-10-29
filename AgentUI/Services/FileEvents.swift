import Foundation
import CoreServices

enum FileEvents {
    static let fallbackInterval: Duration = .seconds(5)

    static func changes(in paths: [String], latency: Duration, every interval: Duration? = nil) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        continuation.yield()
        let watcher = FileEventWatcher(paths: paths, latency: latency) { continuation.yield() }
        let ticker = (interval ?? (watcher == nil ? fallbackInterval : nil)).map { period in
            Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: period) } catch { return }
                    continuation.yield()
                }
            }
        }
        continuation.onTermination = { _ in
            ticker?.cancel()
            watcher?.stop()
        }
        return stream
    }

    @concurrent static func repositoryChanges(at path: String) async -> AsyncStream<Void> {
        let repository = GitRepository.containing(path)
        let paths = [path] + [repository?.gitDirectory.path, repository?.commonDirectory.path].compactMap { $0 }
        return changes(in: Array(Set(paths)), latency: .seconds(1))
    }
}

final class FileEventWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AgentUI.file-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable () -> Void)?

    init?(paths: [String], latency: Duration, onChange: @escaping @Sendable () -> Void) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        let seconds = Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileEventWatcher>.fromOpaque(info).takeUnretainedValue().onChange?()
        }, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), seconds, flags) else { return nil }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    func stop() {
        queue.async { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            onChange = nil
        }
    }
}

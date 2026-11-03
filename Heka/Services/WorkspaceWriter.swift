import Foundation

/// Serial disk I/O off MainActor. A late older request cannot overwrite newer state.
actor WorkspaceWriter {
    private let fileURL: URL
    private var writtenRevision: UInt64 = 0

    init(fileURL: URL) { self.fileURL = fileURL }

    func write(_ snapshot: Workspace, revision: UInt64) throws {
        guard revision > writtenRevision else { return }
        try WorkspaceDisk.save(snapshot, to: fileURL)
        writtenRevision = revision
    }
}

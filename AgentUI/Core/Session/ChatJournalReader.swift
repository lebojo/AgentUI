import Foundation

actor ChatJournalReader<Decoder: ChatJournalDecoder> {
    private var fileID: UInt64?
    private var position: UInt64 = 0
    private var pending = Data()
    private var discarding = false
    private var decoder = Decoder()
    private let initialLimit: UInt64 = 2_097_152
    private let recordLimit = 16_777_216

    func read(_ url: URL) -> [SessionMessage] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64, let inode = attributes[.systemFileNumber] as? UInt64,
              let file = try? FileHandle(forReadingFrom: url) else { return decoder.messages }
        defer { try? file.close() }
        if inode != fileID || size < position {
            fileID = inode
            position = size > initialLimit ? size - initialLimit : 0
            pending = Data()
            discarding = position > 0 && !Self.lineEnds(before: position, in: file)
            decoder = Decoder()
        }
        try? file.seek(toOffset: position)
        while position < size {
            guard let bytes = try? file.read(upToCount: Int(min(65_536, size - position))), !bytes.isEmpty else { break }
            position += UInt64(bytes.count)
            var searchStart = pending.endIndex
            pending.append(bytes)
            var lineStart = pending.startIndex
            while let end = pending[searchStart...].firstIndex(of: 10) {
                let line = Data(pending[lineStart..<end])
                let offset = position - UInt64(pending.endIndex - lineStart)
                if !discarding { decoder.consume(line, offset: offset) }
                discarding = false
                lineStart = pending.index(after: end)
                searchStart = lineStart
            }
            if lineStart > pending.startIndex { pending = Data(pending[lineStart...]) }
            if pending.count > recordLimit {
                if !discarding { decoder.consumeOversized(Data(pending.prefix(65_536))) }
                pending.removeAll(keepingCapacity: false)
                discarding = true
            }
        }
        return decoder.messages
    }

    private static func lineEnds(before position: UInt64, in file: FileHandle) -> Bool {
        guard (try? file.seek(toOffset: position - 1)) != nil, let byte = try? file.read(upToCount: 1) else { return false }
        return byte.first == 10
    }
}

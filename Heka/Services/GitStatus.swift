import Foundation

struct GitStatus: Equatable, Sendable {
    private static let options = ["--literal-pathspecs", "status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=dirty"]
    static let outputLimit = 8_388_608

    private static let leadingFieldCounts: [UInt8: Int] = [UInt8(ascii: "1"): 8, UInt8(ascii: "2"): 9, UInt8(ascii: "u"): 10]

    var headSHA: String?
    var tracking: GitTracking?
    var changes: [GitChange] = []
    var isTruncated = false

    static func arguments(limitedTo paths: [String]?) -> [String] {
        paths.map { options + ["--"] + $0 } ?? options + ["--branch"]
    }

    static func parse(_ data: Data, isTruncated: Bool = false) -> GitStatus {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
        if isTruncated { fields.removeLast() }
        var header = Header()
        var changes: [GitChange] = []
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            index += 1
            if field.first == UInt8(ascii: "#") {
                header.read(String(decoding: field, as: UTF8.self))
                continue
            }
            var original: String?
            if field.first == UInt8(ascii: "2") {
                guard index < fields.endIndex else { break }
                original = String(decoding: fields[index], as: UTF8.self)
                index += 1
            }
            if let change = change(field, originalPath: original) { changes.append(change) }
        }
        return GitStatus(headSHA: header.oid, tracking: header.tracking, changes: changes, isTruncated: isTruncated)
    }

    private static func change(_ field: Data, originalPath: String?) -> GitChange? {
        guard let kind = field.first else { return nil }
        if kind == UInt8(ascii: "?") {
            guard field.count > 2 else { return nil }
            return GitChange(path: String(decoding: field.dropFirst(2), as: UTF8.self), originalPath: nil, indexStatus: "?", worktreeStatus: "?")
        }
        guard let leadingFields = leadingFieldCounts[kind] else { return nil }
        let parts = field.split(separator: UInt8(ascii: " "), maxSplits: leadingFields, omittingEmptySubsequences: false)
        guard parts.count == leadingFields + 1, parts[1].count == 2, let path = parts.last, !path.isEmpty else { return nil }
        let codes = String(decoding: parts[1], as: UTF8.self)
        return GitChange(path: String(decoding: path, as: UTF8.self), originalPath: originalPath,
                         indexStatus: status(codes.prefix(1)), worktreeStatus: status(codes.suffix(1)))
    }

    private static func status(_ code: Substring) -> String {
        code == "." ? " " : String(code)
    }

    private struct Header {
        var oid: String?
        var isBorn = false
        var isDetached = false
        var upstream: String?
        var ahead: Int?

        var tracking: GitTracking? {
            guard isBorn, !isDetached else { return nil }
            guard let upstream else { return GitTracking(upstream: nil) }
            guard let ahead else { return GitTracking(upstream: nil, goneUpstream: upstream) }
            return GitTracking(upstream: upstream, ahead: ahead)
        }

        mutating func read(_ line: String) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "#" else { return }
            let value = String(parts[2])
            switch parts[1] {
            case "branch.oid":
                isBorn = value != "(initial)"
                oid = isBorn ? value : nil
            case "branch.head": isDetached = value == "(detached)"
            case "branch.upstream": upstream = value
            case "branch.ab": ahead = value.split(separator: " ").first.flatMap { Int($0.dropFirst()) }
            default: break
            }
        }
    }
}

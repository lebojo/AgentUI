import Foundation

enum DiffLayout: String, CaseIterable, Identifiable {
    case unified, split
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unified: "Unifié"
        case .split: "Côte à côte"
        }
    }
    var symbol: String {
        switch self {
        case .unified: "rectangle"
        case .split: "rectangle.split.2x1"
        }
    }
}

struct GitDiff: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let sections: [GitDiffSection]
    let lineNumberDigits: Int
    var onlySection: GitDiffSection? { sections.count == 1 ? sections.first : nil }

    init(path: String, sections: [GitDiffSection]) {
        self.path = path
        self.sections = sections
        let highest = sections.flatMap(\.lines).map { max($0.oldNumber ?? 0, $0.newNumber ?? 0) }.max() ?? 0
        lineNumberDigits = max(3, String(highest).count)
    }
}

struct GitDiffSection: Identifiable, Sendable {
    enum Kind: Sendable {
        case staged, unstaged, untracked
        var title: String {
            switch self {
            case .staged: "Modifications indexées"
            case .unstaged: "Modifications non indexées"
            case .untracked: "Nouveau fichier non suivi"
            }
        }
    }

    let kind: Kind
    let patch: String
    let isComplete: Bool
    let lines: [GitDiffLine]
    let rows: [GitDiffRow]
    let additions: Int
    let deletions: Int
    var id: Kind { kind }

    init(kind: Kind, patch: String, isComplete: Bool = true) {
        var lines = GitDiffLine.revealingMixedLineEndings(GitDiffLine.parse(patch))
        if !isComplete {
            lines.append(GitDiffLine(id: lines.count, kind: .meta, text: "Aperçu limité à 128 Ko", oldNumber: nil, newNumber: nil))
        }
        self.kind = kind
        self.patch = patch
        self.isComplete = isComplete
        self.lines = lines
        rows = GitDiffRow.pair(lines)
        additions = lines.count(where: { $0.kind == .addition })
        deletions = lines.count(where: { $0.kind == .deletion })
    }

    static func untracked(path: String, content: TextContent, isExecutable: Bool) -> GitDiffSection {
        var lines = content.text.components(separatedBy: "\n")
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }
        var patch = "diff --git a/\(path) b/\(path)\nnew file mode \(isExecutable ? "100755" : "100644")\n"
        if !lines.isEmpty {
            patch += "--- /dev/null\n+++ b/\(path)\n@@ -0,0 +1\(lines.count == 1 ? "" : ",\(lines.count)") @@\n"
            patch += lines.map { "+\($0)\n" }.joined()
            if !endsWithNewline && !content.isTruncated { patch += "\\ No newline at end of file\n" }
        }
        return GitDiffSection(kind: .untracked, patch: patch, isComplete: !content.isTruncated)
    }
}

struct GitDiffLine: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case context, addition, deletion, hunk, meta
        var isBanner: Bool { self == .hunk || self == .meta }
        var isChange: Bool { self == .addition || self == .deletion }
        var marker: String {
            switch self {
            case .addition: "+"
            case .deletion: "−"
            case .context, .hunk, .meta: " "
            }
        }
    }

    let id: Int
    let kind: Kind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
    var endsWithCarriageReturn = false
    var showsCarriageReturn = false
    var missingFinalNewline = false

    var endingSymbols: String {
        (showsCarriageReturn && endsWithCarriageReturn ? "␍" : "") + (missingFinalNewline ? " ⊘" : "")
    }

    static func parse(_ patch: String) -> [GitDiffLine] {
        let ignoredHeaders = ["diff --git ", "diff --cc ", "diff --combined ", "index ", "--- ", "+++ "]
        var rawLines = patch.components(separatedBy: "\n")
        if rawLines.last == "" { rawLines.removeLast() }
        var result: [GitDiffLine] = []
        var hunk: DiffHunk?
        for rawLine in rawLines {
            let endsWithCarriageReturn = rawLine.hasSuffix("\r")
            let raw = endsWithCarriageReturn ? String(rawLine.dropLast()) : rawLine
            let id = result.count
            if raw.hasPrefix("\\") {
                if !result.isEmpty { result[result.count - 1].missingFinalNewline = true }
            } else if var current = hunk, current.isOpen {
                result.append(current.line(raw, id: id, endsWithCarriageReturn: endsWithCarriageReturn))
                hunk = current
            } else if let header = DiffHunk(header: raw) {
                hunk = header
                result.append(GitDiffLine(id: id, kind: .hunk, text: raw, oldNumber: nil, newNumber: nil))
            } else if !ignoredHeaders.contains(where: raw.hasPrefix) {
                result.append(GitDiffLine(id: id, kind: .meta, text: raw, oldNumber: nil, newNumber: nil))
            }
        }
        return result
    }

    static func revealingMixedLineEndings(_ lines: [GitDiffLine]) -> [GitDiffLine] {
        let endings = Set(lines.filter(\.kind.isChange).map(\.endsWithCarriageReturn))
        guard endings.count > 1 else { return lines }
        return lines.map { line in
            var revealed = line
            revealed.showsCarriageReturn = true
            return revealed
        }
    }
}

private struct DiffHunk {
    var oldNumbers: [Int]
    var oldRemaining: [Int]
    var newNumber: Int
    var newRemaining: Int
    var isOpen: Bool { newRemaining > 0 || oldRemaining.contains { $0 > 0 } }

    init?(header: String) {
        let markers = header.prefix { $0 == "@" }.count
        let parents = markers - 1
        guard parents >= 1, header.dropFirst(markers).hasPrefix(" -") else { return nil }
        let fields = header.dropFirst(markers + 1).split(separator: " ", maxSplits: parents + 1)
        guard fields.count > parents, fields.prefix(parents).allSatisfy({ $0.hasPrefix("-") }), fields[parents].hasPrefix("+") else { return nil }
        let olds = fields.prefix(parents).compactMap { Self.range($0.dropFirst()) }
        guard olds.count == parents, let new = Self.range(fields[parents].dropFirst()) else { return nil }
        oldNumbers = olds.map(\.start)
        oldRemaining = olds.map(\.count)
        newNumber = new.start
        newRemaining = new.count
    }

    mutating func line(_ raw: String, id: Int, endsWithCarriageReturn: Bool) -> GitDiffLine {
        let parents = oldNumbers.count
        let columns = Array(raw.prefix(parents)) + Array(repeating: " ", count: max(0, parents - raw.count))
        let inResult = !columns.contains("-")
        let inParents = columns.map { $0 == "-" || (inResult && $0 != "+") }
        let kind: GitDiffLine.Kind = inResult ? (columns.contains("+") ? .addition : .context) : .deletion
        let line = GitDiffLine(id: id, kind: kind, text: String(raw.dropFirst(parents)),
                               oldNumber: inParents[0] ? oldNumbers[0] : nil, newNumber: inResult ? newNumber : nil,
                               endsWithCarriageReturn: endsWithCarriageReturn)
        for parent in inParents.indices where inParents[parent] {
            oldNumbers[parent] += 1
            oldRemaining[parent] -= 1
        }
        if inResult {
            newNumber += 1
            newRemaining -= 1
        }
        return line
    }

    private static func range(_ text: Substring) -> (start: Int, count: Int)? {
        let parts = text.split(separator: ",")
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        guard parts.count > 1 else { return (start, 1) }
        return Int(parts[1]).map { (start, $0) }
    }
}

struct GitDiffRow: Identifiable, Sendable {
    enum Content: Sendable {
        case banner(GitDiffLine)
        case pair(old: GitDiffLine?, new: GitDiffLine?)
    }

    let id: Int
    let content: Content

    static func pair(_ lines: [GitDiffLine]) -> [GitDiffRow] {
        var rows: [GitDiffRow] = []
        var deletions: [GitDiffLine] = []
        var additions: [GitDiffLine] = []
        func append(_ content: Content) { rows.append(GitDiffRow(id: rows.count, content: content)) }
        func flush() {
            for index in 0..<max(deletions.count, additions.count) {
                append(.pair(old: deletions.indices.contains(index) ? deletions[index] : nil,
                             new: additions.indices.contains(index) ? additions[index] : nil))
            }
            deletions.removeAll(); additions.removeAll()
        }
        for line in lines {
            switch line.kind {
            case .deletion:
                if !additions.isEmpty { flush() }
                deletions.append(line)
            case .addition: additions.append(line)
            case .context: flush(); append(.pair(old: line, new: line))
            case .hunk, .meta: flush(); append(.banner(line))
            }
        }
        flush()
        return rows
    }
}

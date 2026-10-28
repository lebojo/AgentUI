import Foundation

enum Section: Int, Comparable {
    case appStorage
    case environment
    case state
    case stateObject
    case focusState
    case binding
    case observed
    case stored
    case body
    case trailing

    static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .appStorage: "@AppStorage"
        case .environment: "@Environment / @EnvironmentObject"
        case .state: "@State"
        case .stateObject: "@StateObject"
        case .focusState: "@FocusState"
        case .binding: "@Binding"
        case .observed: "@ObservedObject / @ObservedRealmObject / @ObservedResults / @Bindable"
        case .stored: "let / private var { }"
        case .body: "var body"
        case .trailing: "func / init / nested type"
        }
    }
}

enum Wrapper: String, CaseIterable {
    case appStorage = "AppStorage"
    case environment = "Environment"
    case environmentObject = "EnvironmentObject"
    case state = "State"
    case stateObject = "StateObject"
    case focusState = "FocusState"
    case binding = "Binding"
    case observedObject = "ObservedObject"
    case observedRealmObject = "ObservedRealmObject"
    case observedResults = "ObservedResults"
    case bindable = "Bindable"

    var section: Section {
        switch self {
        case .appStorage: .appStorage
        case .environment, .environmentObject: .environment
        case .state: .state
        case .stateObject: .stateObject
        case .focusState: .focusState
        case .binding: .binding
        case .observedObject, .observedRealmObject, .observedResults, .bindable: .observed
        }
    }

    var requiresPrivate: Bool {
        switch self {
        case .binding, .observedObject, .observedRealmObject, .bindable: false
        default: true
        }
    }
}

struct Member {
    var lines: [String]
    let firstLine: Int
    let lastLine: Int
    let blankBefore: Bool
    let section: Section
    let missingPrivate: Bool
    let isDirective: Bool
    let name: String
}

struct ViewDeclaration {
    let name: String
    let headerLine: Int
    let closingLine: Int
    let members: [Member]
}

struct Violation {
    let file: String
    let line: Int
    let message: String
}

struct SourceScanner {
    let lines: [String]

    func depthsAtLineStart() -> [Int] {
        var depths: [Int] = []
        var depth = 0
        var inBlockComment = 0
        var stringDelimiter: String?
        var interpolationStack: [(delimiter: String, parentheses: Int)] = []
        for line in lines {
            let isInsideLiteral = stringDelimiter != nil || inBlockComment > 0 || !interpolationStack.isEmpty
            depths.append(depth + (isInsideLiteral ? 1 : 0))
            if !isInsideLiteral {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") { depth += 1 }
                if trimmed.hasPrefix("#endif") { depth -= 1 }
            }
            let chars = Array(line)
            var index = 0
            while index < chars.count {
                let char = chars[index]
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if inBlockComment > 0 {
                    if char == "*" && next == "/" { inBlockComment -= 1; index += 2; continue }
                    if char == "/" && next == "*" { inBlockComment += 1; index += 2; continue }
                    index += 1
                    continue
                }
                if let delimiter = stringDelimiter {
                    if char == "\\" && next == "(" {
                        interpolationStack.append((delimiter, 0))
                        stringDelimiter = nil
                        index += 2
                        continue
                    }
                    if char == "\\" { index += 2; continue }
                    if String(chars[index..<min(chars.count, index + delimiter.count)]) == delimiter {
                        stringDelimiter = nil
                        index += delimiter.count
                        continue
                    }
                    index += 1
                    continue
                }
                if char == "/" && next == "/" { break }
                if char == "/" && next == "*" { inBlockComment += 1; index += 2; continue }
                if char == "\"" {
                    let isMultiline = index + 2 < chars.count && chars[index + 1] == "\"" && chars[index + 2] == "\""
                    stringDelimiter = isMultiline ? "\"\"\"" : "\""
                    index += isMultiline ? 3 : 1
                    continue
                }
                if !interpolationStack.isEmpty {
                    if char == "(" { interpolationStack[interpolationStack.count - 1].parentheses += 1 }
                    if char == ")" {
                        if let last = interpolationStack.last, last.parentheses == 0 {
                            interpolationStack.removeLast()
                            stringDelimiter = last.delimiter
                            index += 1
                            continue
                        }
                        interpolationStack[interpolationStack.count - 1].parentheses -= 1
                    }
                }
                if "{([".contains(char) { depth += 1 }
                if "})]".contains(char) { depth -= 1 }
                index += 1
            }
            if stringDelimiter == "\"" { stringDelimiter = nil }
        }
        depths.append(depth)
        return depths
    }
}

struct ViewParser {
    let lines: [String]

    private static let viewHeader = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:private|fileprivate|internal|public)\s+)?struct\s+(\w+)(?:<[^>]*>)?\s*:[^{]*\bView\b[^{]*\{"#
    )

    func views() -> [ViewDeclaration] {
        let depths = SourceScanner(lines: lines).depthsAtLineStart()
        var result: [ViewDeclaration] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = Self.viewHeader.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line) else { continue }
            let bodyDepth = depths[index] + 1
            guard let closing = (index + 1..<lines.count).first(where: { depths[$0 + 1] < bodyDepth }) else { continue }
            let members = parseMembers(from: index + 1, to: closing, depth: bodyDepth, depths: depths)
            result.append(ViewDeclaration(name: String(line[nameRange]), headerLine: index, closingLine: closing, members: members))
        }
        return result
    }

    private func parseMembers(from start: Int, to end: Int, depth: Int, depths: [Int]) -> [Member] {
        var members: [Member] = []
        var pending: [String] = []
        var pendingStart: Int?
        var blankBefore = false
        var index = start
        while index < end {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if pending.isEmpty { blankBefore = true } else { pending.append(line) }
                index += 1
                continue
            }
            if pendingStart == nil { pendingStart = index }
            pending.append(line)
            let isLeadingOnly = trimmed.hasPrefix("//") || isAttributeOnly(trimmed)
            if isLeadingOnly {
                index += 1
                continue
            }
            var last = index
            while last + 1 < end, depths[last + 1] > depth || isContinuation(lines[last + 1]) {
                last += 1
                pending.append(lines[last])
            }
            members.append(makeMember(lines: pending, firstLine: pendingStart ?? index, lastLine: last, blankBefore: blankBefore))
            pending = []
            pendingStart = nil
            blankBefore = false
            index = last + 1
        }
        while pending.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { pending.removeLast() }
        if !pending.isEmpty, let pendingStart {
            members.append(makeMember(lines: pending, firstLine: pendingStart, lastLine: pendingStart + pending.count - 1, blankBefore: blankBefore))
        }
        return members
    }

    private func isAttributeOnly(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("@") else { return false }
        let withoutAttributes = trimmed.replacingOccurrences(of: #"@\w+(\([^)]*\))?\s*"#, with: "", options: .regularExpression)
        return withoutAttributes.isEmpty
    }

    private func isContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("}") || trimmed.hasPrefix(".") || trimmed.hasPrefix(")") || trimmed.hasPrefix("]")
    }

    private func makeMember(lines: [String], firstLine: Int, lastLine: Int, blankBefore: Bool) -> Member {
        let code = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        let declaration = code.joined(separator: " ")
        let head = String(declaration.prefix { $0 != "{" && $0 != "=" })
        let wrapper = Wrapper.allCases.first { head.range(of: "@\($0.rawValue)\\b", options: .regularExpression) != nil }
        let tokens = head
            .replacingOccurrences(of: #"@\w+(\([^)]*\))?"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let isPrivate = tokens.contains("private") || tokens.contains("fileprivate")
        let isStatic = tokens.contains("static") || tokens.contains("class")
        let keyword = tokens.first { ["let", "var", "func", "init", "struct", "enum", "class", "actor", "typealias", "protocol", "extension"].contains($0) }
        let name = keyword.flatMap { keyword in tokens.firstIndex(of: keyword).flatMap { tokens.indices.contains($0 + 1) ? tokens[$0 + 1] : nil } }?
            .components(separatedBy: CharacterSet(charactersIn: ":=({<")).first ?? ""
        let section: Section
        var missingPrivate = false
        if let wrapper {
            section = wrapper.section
            missingPrivate = wrapper.requiresPrivate && !isPrivate
        } else if keyword == "var" && name == "body" && !isStatic {
            section = .body
        } else if keyword == "let" && !isStatic {
            section = .stored
        } else if keyword == "var" && !isStatic {
            section = .stored
            missingPrivate = isComputed(declaration) && !isPrivate
        } else {
            section = .trailing
        }
        return Member(
            lines: lines,
            firstLine: firstLine,
            lastLine: lastLine,
            blankBefore: blankBefore,
            section: section,
            missingPrivate: missingPrivate,
            isDirective: code.first?.hasPrefix("#") == true,
            name: name
        )
    }

    private func isComputed(_ declaration: String) -> Bool {
        guard let brace = declaration.firstIndex(of: "{"), !declaration[..<brace].contains("=") else { return false }
        let accessors = declaration[declaration.index(after: brace)...].trimmingCharacters(in: .whitespaces)
        return !accessors.hasPrefix("didSet") && !accessors.hasPrefix("willSet")
    }
}

struct Linter {
    let path: String
    let lines: [String]

    func violations() -> [Violation] {
        ViewParser(lines: lines).views().flatMap(violations(in:))
    }

    private func violations(in view: ViewDeclaration) -> [Violation] {
        var result: [Violation] = []
        var highest: Member?
        let members = view.members.filter { !$0.isDirective }
        for (index, member) in members.enumerated() {
            let line = member.firstLine + 1
            if member.missingPrivate {
                result.append(Violation(file: path, line: line, message: "\(view.name).\(member.name) doit être déclaré private (\(member.section.title))"))
            }
            if let previous = highest, member.section < previous.section {
                result.append(Violation(file: path, line: line, message: "\(view.name).\(member.name) (\(member.section.title)) doit précéder \(previous.name) (\(previous.section.title))"))
            } else {
                highest = member
            }
            guard index > 0 else { continue }
            let previous = members[index - 1]
            if previous.section != member.section && previous.section < member.section && !member.blankBefore {
                result.append(Violation(file: path, line: line, message: "\(view.name).\(member.name) doit être séparé de la section précédente par une ligne vide"))
            }
        }
        return result
    }

    func fixed() -> [String] {
        var output = lines
        for _ in 0..<100 {
            guard let fix = nextFix(in: output) else { break }
            output.replaceSubrange(fix.range, with: fix.lines)
        }
        return output
    }

    private func nextFix(in source: [String]) -> (range: Range<Int>, lines: [String])? {
        for view in ViewParser(lines: source).views() where !view.members.contains(where: \.isDirective) {
            guard let first = view.members.first, let last = view.members.last, !violations(in: view).isEmpty else { continue }
            let range = first.firstLine..<(last.lastLine + 1)
            let rebuilt = rebuilt(view.members)
            if Array(source[range]) != rebuilt { return (range, rebuilt) }
        }
        return nil
    }

    private func rebuilt(_ members: [Member]) -> [String] {
        let ordered = members.enumerated()
            .sorted { ($0.element.section, $0.offset) < ($1.element.section, $1.offset) }
            .map(\.element)
        var result: [String] = []
        for (index, member) in ordered.enumerated() {
            if index > 0 {
                let sameSection = ordered[index - 1].section == member.section
                if !sameSection || member.blankBefore { result.append("") }
            }
            result.append(contentsOf: member.missingPrivate ? addingPrivate(to: member.lines) : member.lines)
        }
        return result
    }

    private func addingPrivate(to lines: [String]) -> [String] {
        guard let index = lines.firstIndex(where: { $0.range(of: #"\b(var|let)\b"#, options: .regularExpression) != nil }) else { return lines }
        var copy = lines
        copy[index] = copy[index].replacingOccurrences(of: #"\b(var|let)\b"#, with: "private $1", options: .regularExpression, range: copy[index].range(of: #"\b(var|let)\b"#, options: .regularExpression))
        return copy
    }
}

func swiftFiles(in paths: [String]) -> [String] {
    paths.flatMap { path -> [String] in
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return path.hasSuffix(".swift") ? [path] : [] }
        let enumerator = FileManager.default.enumerator(atPath: path)
        return (enumerator?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { (path as NSString).appendingPathComponent($0) }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let shouldFix = arguments.contains("--fix")
let roots = arguments.filter { $0 != "--fix" }
let paths = roots.isEmpty ? ["AgentUI"] : roots
let missing = paths.filter { !FileManager.default.fileExists(atPath: $0) }
guard missing.isEmpty else {
    missing.forEach { print("error: \($0) n’existe pas") }
    exit(2)
}
let files = swiftFiles(in: paths)
var remaining: [Violation] = []

for file in files {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
    var lines = source.components(separatedBy: "\n")
    if shouldFix {
        let fixed = Linter(path: file, lines: lines).fixed()
        if fixed != lines {
            try fixed.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
            print("fixed \(file)")
            lines = fixed
        }
    }
    remaining += Linter(path: file, lines: lines).violations()
}

for violation in remaining {
    print("\(violation.file):\(violation.line): error: \(violation.message)")
}
exit(remaining.isEmpty ? 0 : 1)

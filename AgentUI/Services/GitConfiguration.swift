import Foundation

enum GitConfiguration {
    static let hardened = ["core.fsmonitor": "false"]
    static let listingArguments = ["config", "--list", "--show-scope", "--show-origin", "-z"]
    private static let trustedScopes: Set<Substring> = ["system", "global", "command"]
    private static let filterCommands = ["clean", "smudge", "process"]

    static func appending(_ configuration: [String: String], to base: [String: String]) -> [String: String] {
        var environment = base
        var count = max(0, environment["GIT_CONFIG_COUNT"].flatMap(Int.init) ?? 0)
        for (key, value) in configuration.sorted(by: { $0.key < $1.key }) {
            environment["GIT_CONFIG_KEY_\(count)"] = key
            environment["GIT_CONFIG_VALUE_\(count)"] = value
            count += 1
        }
        environment["GIT_CONFIG_COUNT"] = String(count)
        return environment
    }

    struct Entry: Sendable {
        let scope: Substring
        let origin: Substring
        let key: Substring
        let value: Substring?
    }

    static func entries(in listing: Data) -> [Entry] {
        let fields = String(decoding: listing, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        return stride(from: 0, to: fields.count - 2, by: 3).map { index in
            let pair = fields[index + 2].split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            return Entry(scope: fields[index], origin: fields[index + 1], key: pair[0], value: pair.count > 1 ? pair[1] : nil)
        }
    }

    static func untrustedFilterDrivers(in entries: [Entry]) -> Set<String> {
        var drivers: Set<String> = []
        for entry in entries where !trustedScopes.contains(entry.scope) {
            let key = entry.key
            guard key.hasPrefix("filter."), let separator = key.lastIndex(of: "."),
                  separator > key.index(key.startIndex, offsetBy: 6) else { continue }
            drivers.insert(String(key[key.index(key.startIndex, offsetBy: 7)..<separator]))
        }
        return drivers
    }

    static func files(in entries: [Entry], root: String) -> Set<String> {
        var files: Set<String> = []
        for entry in entries where entry.origin.hasPrefix("file:") {
            let origin = absolute(String(entry.origin.dropFirst(5)), relativeTo: root)
            files.insert(origin)
            let isInclude = entry.key == "include.path" || (entry.key.hasPrefix("includeif.") && entry.key.hasSuffix(".path"))
            if isInclude, let value = entry.value, !value.isEmpty {
                files.insert(absolute(String(value), relativeTo: (origin as NSString).deletingLastPathComponent))
            }
        }
        return files
    }

    private static func absolute(_ path: String, relativeTo directory: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let full = (expanded as NSString).isAbsolutePath ? expanded : (directory as NSString).appendingPathComponent(expanded)
        return (full as NSString).standardizingPath
    }

    static func disabling(filterDrivers drivers: Set<String>) -> [String: String] {
        var configuration: [String: String] = [:]
        for driver in drivers {
            for command in filterCommands { configuration["filter.\(driver).\(command)"] = "" }
            configuration["filter.\(driver).required"] = "false"
        }
        return configuration
    }
}

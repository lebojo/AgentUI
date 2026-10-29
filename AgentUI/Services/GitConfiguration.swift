import Foundation

enum GitConfiguration {
    static let hardened = ["core.fsmonitor": "false"]
    static let listingArguments = ["config", "--list", "--name-only", "--show-scope", "-z"]
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

    static func untrustedFilterDrivers(in listing: Data) -> Set<String> {
        let fields = String(decoding: listing, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        var drivers: Set<String> = []
        for index in stride(from: 0, to: fields.count - 1, by: 2) where !trustedScopes.contains(fields[index]) {
            let key = fields[index + 1]
            guard key.hasPrefix("filter."), let separator = key.lastIndex(of: "."),
                  separator > key.index(key.startIndex, offsetBy: 6) else { continue }
            drivers.insert(String(key[key.index(key.startIndex, offsetBy: 7)..<separator]))
        }
        return drivers
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

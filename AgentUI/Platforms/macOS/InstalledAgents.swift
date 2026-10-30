import Foundation
import Observation

@MainActor @Observable final class InstalledAgents {
    private(set) var agents: [ConversationAgent] = []
    @ObservationIgnored private var refreshedAt: ContinuousClock.Instant?

    func refresh() async {
        guard refreshedAt.map({ $0.duration(to: .now) >= .seconds(60) }) ?? true else { return }
        refreshedAt = .now
        let detected = await Self.detect()
        if agents != detected { agents = detected }
    }

    @concurrent private static func detect() async -> [ConversationAgent] {
        let configuredShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = FileManager.default.isExecutableFile(atPath: configuredShell) ? configuredShell : "/bin/zsh"
        let lookups = ConversationAgent.allCases.map { "command -v \($0.rawValue) >/dev/null 2>&1 && echo \($0.rawValue)" }
        let script = (lookups + ["true"]).joined(separator: "; ")
        guard let output = try? await CommandRunner.run(URL(fileURLWithPath: shell), ["-l", "-i", "-c", script], at: NSHomeDirectory(),
                                                        timeout: 15, limit: 65_536, readOnly: true) else { return [] }
        let names = Set(String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        return ConversationAgent.allCases.filter { names.contains($0.rawValue) }
    }
}

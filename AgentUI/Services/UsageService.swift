import Foundation

enum UsageService {
    private static let session = URLSession(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }())

    @concurrent static func fetch(_ provider: UsageProvider) async throws -> ProviderUsage? {
        switch provider {
        case .claude: try await fetchClaude()
        case .codex: try await fetchCodex()
        }
    }

    private static func fetchClaude() async throws -> ProviderUsage? {
        guard let token = await claudeToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        return try ProviderUsage.claude(from: try await load(request, provider: .claude))
    }

    private static func fetchCodex() async throws -> ProviderUsage? {
        guard let auth = codexAuth() else { return nil }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        if let account = auth.accountID { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        return try ProviderUsage.codex(from: try await load(request, provider: .codex))
    }

    private static func load(_ request: URLRequest, provider: UsageProvider) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw UsageError(message: "Connexion \(provider.title) expirée. Relance \(provider.title) dans un terminal pour la renouveler.")
        case 429: throw UsageError(message: "Trop de requêtes. Nouvel essai automatique dans quelques minutes.")
        default: throw UsageError(message: "Le service \(provider.title) a répondu \(status).")
        }
    }

    private static func claudeToken() async -> String? {
        let security = URL(fileURLWithPath: "/usr/bin/security")
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let data = try? await ReadCommand.run(security, ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
                                                 at: home.path, timeout: 10, limit: 65_536),
           let token = ClaudeCredentials.accessToken(in: data) {
            return token
        }
        let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".claude")
        return (try? Data(contentsOf: directory.appendingPathComponent(".credentials.json"))).flatMap(ClaudeCredentials.accessToken)
    }

    private static func codexAuth() -> CodexAuth? {
        let directory = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("auth.json")),
              let file = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
              let token = file.tokens?.accessToken, !token.isEmpty else { return nil }
        return CodexAuth(accessToken: token, accountID: file.tokens?.accountID)
    }
}

struct UsageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ClaudeCredentials {
    static func accessToken(in data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let file = try? JSONDecoder().decode(File.self, from: Data(text.utf8)),
              let token = file.claudeAiOauth?.accessToken, !token.isEmpty else { return nil }
        return token
    }

    private struct File: Decodable {
        struct OAuth: Decodable { let accessToken: String? }
        let claudeAiOauth: OAuth?
    }
}

private struct CodexAuth {
    let accessToken: String
    let accountID: String?
}

private struct CodexAuthFile: Decodable {
    struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
    let tokens: Tokens?
}

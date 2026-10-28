import Foundation

enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
    var signInHint: String {
        switch self {
        case .claude: "Ouvre Claude Code dans un terminal pour te connecter avec ton abonnement Claude."
        case .codex: "Lance « codex login » dans un terminal pour te connecter avec ton compte ChatGPT."
        }
    }
    var signInCommand: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex", "login"]
        }
    }
}

enum UsageWindowKind: Hashable, Sendable {
    case session(minutes: Int)
    case weekly
    case weeklyModel(String)
    case monthlySpend

    var title: String {
        switch self {
        case .session(let minutes): minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
        case .weekly: "Semaine"
        case .weeklyModel(let model): "Semaine · \(model)"
        case .monthlySpend: "Crédits du mois"
        }
    }
    var shortTitle: String {
        switch self {
        case .session: title
        case .weekly: "7 j"
        case .weeklyModel(let model): "7 j · \(model)"
        case .monthlySpend: "Mois"
        }
    }
    var detail: String {
        switch self {
        case .session(let minutes): "Fenêtre glissante de \(minutes % 60 == 0 ? "\(minutes / 60) heures" : "\(minutes) minutes")"
        case .weekly: "Tous modèles confondus, sur 7 jours"
        case .weeklyModel(let model): "Limite propre à \(model), sur 7 jours"
        case .monthlySpend: "Usage supplémentaire facturé au-delà du forfait"
        }
    }
    var isSession: Bool {
        if case .session = self { return true }
        return false
    }
}

struct UsageWindow: Identifiable, Equatable, Sendable {
    let kind: UsageWindowKind
    let usedPercent: Double
    let resetsAt: Date?
    var id: UsageWindowKind { kind }
    var fraction: Double { min(1, max(0, usedPercent / 100)) }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
    var level: UsageLevel { UsageLevel(usedPercent: usedPercent) }
}

enum UsageLevel: Sendable {
    case comfortable, warning, critical
    init(usedPercent: Double) {
        self = usedPercent >= 90 ? .critical : (usedPercent >= 70 ? .warning : .comfortable)
    }
}

struct UsageSpend: Equatable, Sendable {
    let isEnabled: Bool
    let spent: Double
    let limit: Double
    let currency: String
}

struct ProviderUsage: Equatable, Sendable {
    let provider: UsageProvider
    let plan: String?
    let windows: [UsageWindow]
    let spend: UsageSpend?
    let updatedAt: Date

    var session: UsageWindow? { windows.first { $0.kind.isSession } }
    var weekly: UsageWindow? { windows.first { $0.kind == .weekly } }
    var mostConstrained: UsageWindow? { windows.max { $0.usedPercent < $1.usedPercent } }
    var headline: UsageWindow? { session ?? mostConstrained }
}

enum UsageState: Equatable, Sendable {
    case loading
    case signedOut
    case loaded(ProviderUsage)
    case failed(String, last: ProviderUsage?)

    var usage: ProviderUsage? {
        switch self {
        case .loaded(let usage): usage
        case .failed(_, let last): last
        case .loading, .signedOut: nil
        }
    }
    var error: String? {
        if case .failed(let message, _) = self { return message }
        return nil
    }
}

enum UsageCountdown {
    static func text(until date: Date, from now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return "maintenant" }
        let minutes = (seconds + 59) / 60
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return hours > 0 ? "\(days) j \(hours) h" : "\(days) j" }
        if hours > 0 { return rest > 0 ? "\(hours) h \(String(format: "%02d", rest))" : "\(hours) h" }
        return "\(minutes) min"
    }
}

extension ProviderUsage {
    static func claude(from data: Data, now: Date = .now) throws -> ProviderUsage {
        let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: data)
        var windows: [UsageWindow] = []
        if let window = payload.windows["five_hour"]?.window(.session(minutes: 300)) { windows.append(window) }
        if let window = payload.windows["seven_day"]?.window(.weekly) { windows.append(window) }
        let models = payload.windows
            .filter { $0.key.hasPrefix("seven_day_") }
            .sorted { $0.key < $1.key }
            .compactMap { key, value in value.window(.weeklyModel(modelName(key.dropFirst("seven_day_".count)))) }
        windows += models
        let scoped = (payload.limits ?? [])
            .filter { $0.kind == "weekly_scoped" }
            .compactMap { limit -> UsageWindow? in
                guard let name = limit.scope?.model?.displayName, let percent = limit.percent,
                      !windows.contains(where: { $0.kind == .weeklyModel(name) }) else { return nil }
                return UsageWindow(kind: .weeklyModel(name), usedPercent: percent, resetsAt: limit.resetsAt?.date)
            }
        windows += scoped
        let spend = payload.extraUsage?.spend
        if windows.isEmpty, let spend, spend.limit > 0 {
            windows.append(UsageWindow(kind: .monthlySpend, usedPercent: spend.spent / spend.limit * 100, resetsAt: nil))
        }
        return ProviderUsage(provider: .claude, plan: nil, windows: windows, spend: spend, updatedAt: now)
    }

    static func codex(from data: Data, now: Date = .now) throws -> ProviderUsage {
        let payload = try JSONDecoder().decode(CodexUsagePayload.self, from: data)
        let windows = [payload.rateLimit?.primaryWindow, payload.rateLimit?.secondaryWindow]
            .compactMap { $0?.window }
            .sorted { $0.kind.isSession && !$1.kind.isSession }
        return ProviderUsage(provider: .codex, plan: payload.planType.map(planName), windows: windows, spend: nil, updatedAt: now)
    }

    private static func modelName(_ key: Substring) -> String {
        key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func planName(_ plan: String) -> String {
        plan.prefix(1).uppercased() + plan.dropFirst()
    }
}

private struct UsageTimestamp: Decodable {
    let date: Date?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        } else if let value = try? container.decode(String.self) {
            date = (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? Double(value).map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
        } else {
            date = nil
        }
    }
}

private struct UsageKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private struct ClaudeUsagePayload: Decodable {
    let windows: [String: ClaudeWindowPayload]
    let extraUsage: ClaudeExtraUsagePayload?
    let limits: [ClaudeLimitPayload]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: UsageKey.self)
        var windows: [String: ClaudeWindowPayload] = [:]
        for key in container.allKeys where key.stringValue.hasPrefix("five_hour") || key.stringValue.hasPrefix("seven_day") {
            if let window = try? container.decode(ClaudeWindowPayload.self, forKey: key) { windows[key.stringValue] = window }
        }
        self.windows = windows
        extraUsage = try? container.decode(ClaudeExtraUsagePayload.self, forKey: UsageKey(stringValue: "extra_usage"))
        limits = try? container.decode([ClaudeLimitPayload].self, forKey: UsageKey(stringValue: "limits"))
    }
}

private struct ClaudeWindowPayload: Decodable {
    let utilization: Double?
    let resetsAt: UsageTimestamp?
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
    func window(_ kind: UsageWindowKind) -> UsageWindow? {
        utilization.map { UsageWindow(kind: kind, usedPercent: min(100, max(0, $0)), resetsAt: resetsAt?.date) }
    }
}

private struct ClaudeExtraUsagePayload: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let currency: String?
    let decimalPlaces: Int?
    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case currency
        case decimalPlaces = "decimal_places"
    }
    var spend: UsageSpend? {
        guard let monthlyLimit else { return nil }
        let divisor = pow(10, Double(decimalPlaces ?? 2))
        return UsageSpend(isEnabled: isEnabled == true, spent: (usedCredits ?? 0) / divisor, limit: monthlyLimit / divisor,
                          currency: currency ?? "USD")
    }
}

private struct ClaudeLimitPayload: Decodable {
    struct Scope: Decodable {
        struct Model: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        let model: Model?
    }
    let kind: String?
    let percent: Double?
    let resetsAt: UsageTimestamp?
    let scope: Scope?
    enum CodingKeys: String, CodingKey {
        case kind, percent, scope
        case resetsAt = "resets_at"
    }
}

private struct CodexUsagePayload: Decodable {
    struct RateLimit: Decodable {
        let primaryWindow: CodexWindowPayload?
        let secondaryWindow: CodexWindowPayload?
        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }
    let planType: String?
    let rateLimit: RateLimit?
    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private struct CodexWindowPayload: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAt: UsageTimestamp?
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
    var window: UsageWindow? {
        guard let usedPercent else { return nil }
        let minutes = Int(((limitWindowSeconds ?? 18_000) / 60).rounded(.up))
        let kind: UsageWindowKind = minutes <= 1440 ? .session(minutes: minutes) : .weekly
        return UsageWindow(kind: kind, usedPercent: min(100, max(0, usedPercent)), resetsAt: resetAt?.date)
    }
}

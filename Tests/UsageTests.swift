import Foundation

enum UsageTests {
    @MainActor static func run() async throws {
        let require = CoreTests.require
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let claudeJSON = """
        {"five_hour":{"utilization":42.4,"resets_at":"2027-01-15T10:00:00.123456+00:00"},
         "seven_day":{"utilization":18,"resets_at":"2027-01-20T08:00:00Z"},
         "seven_day_opus":{"utilization":3,"resets_at":null},
         "seven_day_oauth_apps":null,
         "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1240,"utilization":24.8}}
        """
        let claude = try ProviderUsage.claude(from: Data(claudeJSON.utf8), now: now)
        try require(claude.session?.usedPercent == 42.4 && claude.session?.kind == .session(minutes: 300), "Claude five-hour window maps to a session")
        let sessionReset = try Date("2027-01-15T10:00:00Z", strategy: .iso8601)
        try require(abs(claude.session?.resetsAt?.timeIntervalSince(sessionReset) ?? 9) < 1, "Claude reset parses fractional ISO 8601")
        try require(claude.weekly?.usedPercent == 18, "Claude seven-day window maps to weekly")
        try require(claude.windows.contains { $0.kind == .weeklyModel("Opus") && $0.resetsAt == nil }, "Claude model windows keep their name")
        try require(claude.windows.count == 3, "Null Claude windows are skipped")
        try require(claude.spend == UsageSpend(isEnabled: true, spent: 12.4, limit: 50, currency: "USD"), "Claude extra usage converts minor units")

        let scoped = try ProviderUsage.claude(from: Data(#"{"five_hour":{"utilization":120},"limits":[{"kind":"weekly_scoped","percent":7,"resets_at":1800003600,"scope":{"model":{"display_name":"Fable"}}}]}"#.utf8))
        try require(scoped.session?.usedPercent == 100, "Utilization is clamped")
        try require(scoped.windows.contains { $0.kind == .weeklyModel("Fable") && $0.resetsAt == Date(timeIntervalSince1970: 1_800_003_600) }, "Scoped weekly limits are read")

        let enterprise = try ProviderUsage.claude(from: Data(#"{"extra_usage":{"is_enabled":true,"monthly_limit":10000,"used_credits":2500}}"#.utf8))
        try require(enterprise.windows.first?.kind == .monthlySpend && enterprise.windows.first?.usedPercent == 25, "Spend becomes the limit without plan windows")
        print("PASS Claude usage parsing")

        let codexJSON = """
        {"plan_type":"pro","rate_limit":{
          "primary_window":{"used_percent":64,"limit_window_seconds":604800,"reset_at":1800086400},
          "secondary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1800003600}}}
        """
        let codex = try ProviderUsage.codex(from: Data(codexJSON.utf8), now: now)
        try require(codex.plan == "Pro", "Codex plan is capitalized")
        try require(codex.windows.first?.kind == .session(minutes: 300) && codex.session?.usedPercent == 12, "Codex windows are classified by duration, session first")
        try require(codex.weekly?.usedPercent == 64 && codex.weekly?.resetsAt == Date(timeIntervalSince1970: 1_800_086_400), "Codex weekly window keeps its reset")
        try require(codex.mostConstrained?.kind == .weekly, "Most constrained window has the highest usage")
        print("PASS Codex usage parsing")

        try require(ClaudeCredentials.accessToken(in: Data("{\"claudeAiOauth\":{\"accessToken\":\"abc\"}}\n".utf8)) == "abc", "Keychain JSON yields the access token")
        try require(ClaudeCredentials.accessToken(in: Data("{}".utf8)) == nil, "Missing OAuth credentials mean signed out")

        try require(UsageCountdown.text(until: now.addingTimeInterval(2 * 3600 + 13 * 60), from: now) == "2 h 13", "Hours and minutes countdown")
        try require(UsageCountdown.text(until: now.addingTimeInterval(3 * 3600), from: now) == "3 h", "Whole hours countdown")
        try require(UsageCountdown.text(until: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 20), from: now) == "3 j 4 h", "Days countdown drops minutes")
        try require(UsageCountdown.text(until: now.addingTimeInterval(30), from: now) == "1 min", "Under a minute shows one minute")
        try require(UsageCountdown.text(until: now.addingTimeInterval(-5), from: now) == "maintenant", "Past reset")
        try require(UsageLevel(usedPercent: 69) == .comfortable && UsageLevel(usedPercent: 70) == .warning && UsageLevel(usedPercent: 95) == .critical, "Usage levels")
        print("PASS usage countdown and levels")

        let failing = Flag()
        let store = UsageStore { provider in
            switch provider {
            case .claude:
                if failing.value { throw UsageError(message: "Trop de requêtes.") }
                return claude
            case .codex: return nil
            }
        }
        await store.refresh()
        try require(store.state(for: .claude) == .loaded(claude) && store.state(for: .codex) == .signedOut, "Store loads each provider")
        try require(store.connectedProviders == [.claude], "Signed-out providers are hidden from the bar")
        failing.value = true
        await store.refresh(minimumAge: 3600)
        try require(store.state(for: .claude) == .loaded(claude), "Recent data is not refetched")
        await store.refresh()
        try require(store.state(for: .claude) == .failed("Trop de requêtes.", last: claude), "A failure keeps the last usage")
        try require(store.connectedProviders == [.claude], "A failing provider stays visible")
        print("PASS usage store")

        let signedIn = Flag()
        let signIn = UsageStore { provider in
            guard provider == .codex, signedIn.value else { return nil }
            return codex
        }
        await signIn.refresh()
        try require(signIn.isSignedOutEverywhere && signIn.connectedProviders.isEmpty, "Signed-out everywhere is detected")
        let waiting = Task { await signIn.waitForSignIn(.codex, interval: .milliseconds(10), timeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        try require(signIn.pendingSignIns == [.codex] && signIn.state(for: .codex) == .signedOut, "Sign-in waits while credentials are missing")
        signedIn.value = true
        await waiting.value
        try require(signIn.pendingSignIns.isEmpty && signIn.state(for: .codex) == .loaded(codex), "Usage appears once signed in")
        await signIn.waitForSignIn(.claude, interval: .milliseconds(5), timeout: .milliseconds(30))
        try require(signIn.pendingSignIns.isEmpty && signIn.state(for: .claude) == .signedOut, "Sign-in wait gives up after its timeout")
        print("PASS usage sign-in wait")
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }
}

import Foundation
import Observation

@MainActor @Observable final class UsageStore {
    private(set) var states: [UsageProvider: UsageState] = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { ($0, .loading) })
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var pendingSignIns: Set<UsageProvider> = []

    typealias Query = @Sendable (UsageProvider) async throws -> ProviderUsage?
    @ObservationIgnored private let query: Query
    @ObservationIgnored private var signInTasks: [UsageProvider: Task<Void, Never>] = [:]

    init(query: @escaping Query = { try await UsageService.fetch($0) }) {
        self.query = query
    }

    var connectedProviders: [UsageProvider] {
        UsageProvider.allCases.filter { state(for: $0).usage != nil || state(for: $0).error != nil }
    }

    var isSignedOutEverywhere: Bool {
        UsageProvider.allCases.allSatisfy { state(for: $0) == .signedOut }
    }

    func watchSignIn(_ provider: UsageProvider) {
        signInTasks[provider]?.cancel()
        signInTasks[provider] = Task(priority: .utility) { await waitForSignIn(provider) }
    }

    func waitForSignIn(_ provider: UsageProvider, interval: Duration = .seconds(5), timeout: Duration = .seconds(600)) async {
        pendingSignIns.insert(provider)
        defer { pendingSignIns.remove(provider) }
        let deadline = ContinuousClock.now + timeout
        while !Task.isCancelled, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: interval) } catch { return }
            let result = await Result { try await query(provider) }
            guard !Task.isCancelled else { return }
            if case .success(nil) = result { continue }
            apply(result, to: provider)
            return
        }
    }

    func state(for provider: UsageProvider) -> UsageState {
        states[provider] ?? .loading
    }

    func monitor(interval: Duration = .seconds(300)) async {
        while !Task.isCancelled {
            await refresh(minimumAge: 60)
            do { try await Task.sleep(for: interval) } catch { break }
        }
    }

    func refresh(minimumAge: TimeInterval = 0) async {
        guard !isRefreshing, Date().timeIntervalSince(lastRefresh ?? .distantPast) >= minimumAge else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let query = query
        await withTaskGroup(of: (UsageProvider, Result<ProviderUsage?, Error>).self) { group in
            for provider in UsageProvider.allCases {
                group.addTask { (provider, await Result { try await query(provider) }) }
            }
            for await (provider, result) in group {
                apply(result, to: provider)
            }
        }
        lastRefresh = Date()
    }

    private func apply(_ result: Result<ProviderUsage?, Error>, to provider: UsageProvider) {
        switch result {
        case .success(let usage?): states[provider] = .loaded(usage)
        case .success(nil): states[provider] = .signedOut
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            states[provider] = .failed(error.localizedDescription, last: state(for: provider).usage)
        }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) }
        catch { self = .failure(error) }
    }
}

import Foundation
import NotchChatHistoryFeature

private struct TestCase {
    let name: String
    let run: () async throws -> Void
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

@MainActor
private enum GeminiLiveChatHistoryStoreTests {
    static func suggestionPrefersMostRecentPrefixMatchOverHigherUseCount() throws {
        let (defaults, suiteName, defaultsKey) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GeminiLiveChatHistoryStore(userDefaults: defaults, defaultsKey: defaultsKey)
        store.save("open calendar")
        store.save("open calendar")
        store.save("open camera")

        try expectEqual(store.getSuggestion(for: "open c"), "open camera")
        try expectEqual(store.history, ["open camera", "open calendar"])
    }

    static func exactPrefixFallsBackToNextMostRecentCompletion() throws {
        let (defaults, suiteName, defaultsKey) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GeminiLiveChatHistoryStore(userDefaults: defaults, defaultsKey: defaultsKey)
        store.save("run tests")
        store.save("run")

        try expectEqual(store.getSuggestion(for: "run"), "run tests")
    }

    static func recencyRankingSurvivesReload() throws {
        let (defaults, suiteName, defaultsKey) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GeminiLiveChatHistoryStore(userDefaults: defaults, defaultsKey: defaultsKey)
        store.save("open calendar")
        store.save("open camera")
        defaults.synchronize()

        let reloaded = GeminiLiveChatHistoryStore(userDefaults: defaults, defaultsKey: defaultsKey)

        try expectEqual(reloaded.getSuggestion(for: "open c"), "open camera")
        try expectEqual(reloaded.history, ["open camera", "open calendar"])
    }

    static func suggestionStillRequiresPrefixMatch() throws {
        let (defaults, suiteName, defaultsKey) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GeminiLiveChatHistoryStore(userDefaults: defaults, defaultsKey: defaultsKey)
        store.save("calendar")

        try expectNil(store.getSuggestion(for: "camera"))
    }

    private static func makeIsolatedDefaults() -> (
        defaults: UserDefaults,
        suiteName: String,
        defaultsKey: String
    ) {
        let suiteName = "dev.notch.chat-history-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName, "history")
    }
}

@MainActor
private func buildTestCases() -> [TestCase] {
    [
        TestCase(
            name: "history/suggestion prefers most recent prefix match over higher use count",
            run: { try GeminiLiveChatHistoryStoreTests.suggestionPrefersMostRecentPrefixMatchOverHigherUseCount() }
        ),
        TestCase(
            name: "history/exact prefix falls back to next most recent completion",
            run: { try GeminiLiveChatHistoryStoreTests.exactPrefixFallsBackToNextMostRecentCompletion() }
        ),
        TestCase(
            name: "history/recency ranking survives reload",
            run: { try GeminiLiveChatHistoryStoreTests.recencyRankingSurvivesReload() }
        ),
        TestCase(
            name: "history/suggestion still requires prefix match",
            run: { try GeminiLiveChatHistoryStoreTests.suggestionStillRequiresPrefixMatch() }
        ),
    ]
}

@MainActor
private func runAll() async -> Int {
    let tests = buildTestCases()
    var passed = 0
    var failures: [(name: String, error: Error)] = []

    for test in tests {
        do {
            try await test.run()
            print("PASS  \(test.name)")
            passed += 1
        } catch {
            print("FAIL  \(test.name)")
            print("        \(error)")
            failures.append((test.name, error))
        }
    }

    print("")
    print("========== NotchChatHistoryTests summary ==========")
    print("\(passed)/\(tests.count) passed, \(failures.count) failed")
    if !failures.isEmpty {
        print("")
        print("Failing tests:")
        for failure in failures {
            print("  - \(failure.name)")
        }
    }

    return failures.isEmpty ? 0 : 1
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw TestFailure(message: "Expected \(expected), got \(actual)")
    }
}

private func expectNil<T>(_ actual: T?) throws {
    guard actual == nil else {
        throw TestFailure(message: "Expected nil, got \(String(describing: actual))")
    }
}

let exitCode = await runAll()
exit(Int32(exitCode))

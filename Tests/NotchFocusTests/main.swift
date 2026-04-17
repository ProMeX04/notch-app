import Foundation

struct TestCase {
    let name: String
    let run: () async throws -> Void
}

@MainActor
func buildTestCases() -> [TestCase] {
    [
        TestCase(
            name: "focus/wake advances elapsed phase once and stays idempotent",
            run: PomodoroViewModelTests.wakeAdvancesElapsedPhaseOnce
        ),
        TestCase(
            name: "focus/restore catches up multiple expired phases within limit",
            run: PomodoroViewModelTests.restoreCatchUpMultipleExpiredPhases
        ),
        TestCase(
            name: "focus/derived minutes reflect second overrides",
            run: PomodoroViewModelTests.derivedMinutesReflectSecondOverrides
        ),
        TestCase(
            name: "focus/manual pause then skip does not auto resume",
            run: PomodoroViewModelTests.manualPauseThenSkipDoesNotAutoResume
        ),
        TestCase(
            name: "focus/cycle indicators stay consistent across edges",
            run: PomodoroViewModelTests.cycleIndicatorsStayConsistentAcrossEdges
        ),
    ]
}

@MainActor
func runAll() async -> Int {
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
    print("========== NotchFocusTests summary ==========")
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

let exitCode = await runAll()
exit(Int32(exitCode))

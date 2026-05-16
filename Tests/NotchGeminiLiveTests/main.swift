import Foundation

struct TestCase {
    let name: String
    let run: @MainActor () async throws -> Void
}

extension TestCase {
    init(name: String, run: @escaping @MainActor () throws -> Void) {
        self.name = name
        self.run = { try run() }
    }
}

@MainActor
func buildTestCases() -> [TestCase] {
    ExecApprovalCoordinatorTests.allTests
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
    print("========== NotchGeminiLiveTests summary ==========")
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

import Foundation
import NotchBridgeParserCore

// MARK: - Test runner

struct TestCase {
    let name: String
    let run: () throws -> Void
}

func runAll() -> Int {
    let tests = buildTestCases()
    var passed = 0
    var failures: [(name: String, error: Error)] = []

    for test in tests {
        do {
            try test.run()
            print("PASS  \(test.name)")
            passed += 1
        } catch {
            print("FAIL  \(test.name)")
            print("        \(error)")
            failures.append((test.name, error))
        }
    }

    print("")
    print("========== NotchBridgeParserTests summary ==========")
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

func buildTestCases() -> [TestCase] {
    [
        TestCase(
            name: "parser/single complete unmasked text frame decodes result",
            run: FrameParserTests.singleCompleteUnmaskedTextFrame_decodesResult
        ),
        TestCase(
            name: "parser/masked client text frame decodes result",
            run: FrameParserTests.maskedClientTextFrame_decodesResult
        ),
        TestCase(
            name: "parser/fragmented text message across continuation frames assembles",
            run: FrameParserTests.fragmentedTextMessage_acrossContinuationFrames_assembles
        ),
        TestCase(
            name: "parser/ping frame does not crash and surfaces pong path",
            run: FrameParserTests.pingFrame_doesNotCrash_surfacesPongPath
        ),
        TestCase(
            name: "parser/oversized payload is rejected without trap",
            run: FrameParserTests.oversizedPayload_isRejected
        ),
        TestCase(
            name: "parser/malformed extended-length frame is rejected without trap",
            run: FrameParserTests.malformedExtendedLengthFrame_isRejected
        ),
        TestCase(
            name: "parser/close frame surfaces close message",
            run: FrameParserTests.closeFrame_surfacesCloseMessage
        ),
        TestCase(
            name: "parser/continuation frame completion produces exactly one message",
            run: FrameParserTests.continuationFrameCompletion_producesExactlyOneMessage
        ),
    ]
}

let exitCode = runAll()
exit(Int32(exitCode))

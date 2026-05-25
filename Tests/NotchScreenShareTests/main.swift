import CoreGraphics
import Foundation
import NotchScreenShareCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct TestCase {
    let name: String
    let run: () throws -> Void
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(message: message) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(message: "\(message): expected \(expected), got \(actual)")
    }
}

func expectRectEqual(_ actual: CGRect, _ expected: CGRect, _ message: String) throws {
    try expectEqual(actual.origin.x, expected.origin.x, "\(message) minX")
    try expectEqual(actual.origin.y, expected.origin.y, "\(message) minY")
    try expectEqual(actual.size.width, expected.size.width, "\(message) width")
    try expectEqual(actual.size.height, expected.size.height, "\(message) height")
}

let primaryDisplay = ScreenShareDisplayDescriptor(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    pixelWidth: 2880,
    pixelHeight: 1800
)

let leftDisplay = ScreenShareDisplayDescriptor(
    id: 2,
    frame: CGRect(x: -1280, y: 0, width: 1280, height: 720),
    pixelWidth: 1280,
    pixelHeight: 720
)

func buildTestCases() -> [TestCase] {
    [
        TestCase(
            name: "selected small region does not resolve to full display capture",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: 100, y: 120, width: 320, height: 180),
                    displays: [primaryDisplay]
                )

                guard let plan else { throw TestFailure(message: "expected capture plan") }
                try expectEqual(plan.displayID, primaryDisplay.id, "display id")
                try expectRectEqual(
                    plan.sourceRect,
                    CGRect(x: 100, y: 600, width: 320, height: 180),
                    "source rect"
                )
                try expectEqual(plan.outputWidth, 640, "output width")
                try expectEqual(plan.outputHeight, 360, "output height")
                try expect(plan.sourceRect != primaryDisplay.frame, "source rect should not be the full display")
                try expect(plan.outputWidth != primaryDisplay.pixelWidth, "output width should not be the full display width")
                try expect(plan.outputHeight != primaryDisplay.pixelHeight, "output height should not be the full display height")
            }
        ),
        TestCase(
            name: "negative origin display subtracts display origin",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: -1180, y: 40, width: 200, height: 100),
                    displays: [primaryDisplay, leftDisplay]
                )

                guard let plan else { throw TestFailure(message: "expected capture plan") }
                try expectEqual(plan.displayID, leftDisplay.id, "display id")
                try expectRectEqual(
                    plan.sourceRect,
                    CGRect(x: 100, y: 580, width: 200, height: 100),
                    "source rect"
                )
                try expectEqual(plan.outputWidth, 200, "output width")
                try expectEqual(plan.outputHeight, 100, "output height")
            }
        ),
        TestCase(
            name: "retina display scales cropped output dimensions",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: 10, y: 20, width: 101, height: 51),
                    displays: [primaryDisplay]
                )

                guard let plan else { throw TestFailure(message: "expected capture plan") }
                try expectEqual(plan.outputWidth, 202, "output width")
                try expectEqual(plan.outputHeight, 102, "output height")
            }
        ),
        TestCase(
            name: "spanning region chooses largest overlap and clips to display",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: -200, y: 100, width: 500, height: 200),
                    displays: [leftDisplay, primaryDisplay]
                )

                guard let plan else { throw TestFailure(message: "expected capture plan") }
                try expectEqual(plan.displayID, primaryDisplay.id, "display id")
                try expectRectEqual(
                    plan.screenRect,
                    CGRect(x: 0, y: 100, width: 300, height: 200),
                    "screen rect"
                )
                try expectRectEqual(
                    plan.sourceRect,
                    CGRect(x: 0, y: 600, width: 300, height: 200),
                    "source rect"
                )
            }
        ),
        TestCase(
            name: "offscreen region returns nil",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: 2000, y: 2000, width: 100, height: 100),
                    displays: [primaryDisplay]
                )

                try expect(plan == nil, "expected no capture plan")
            }
        ),
        TestCase(
            name: "zero size region returns nil",
            run: {
                let plan = ScreenShareCaptureGeometry.resolveCapturePlan(
                    requestedRect: CGRect(x: 100, y: 100, width: 0, height: 50),
                    displays: [primaryDisplay]
                )

                try expect(plan == nil, "expected no capture plan")
            }
        ),
        TestCase(
            name: "screen frame filter suppresses unchanged frames",
            run: {
                var filter = ScreenShareFrameChangeFilter()
                let firstFrame = Data([0x01, 0x02, 0x03])

                try expect(filter.shouldSend(firstFrame), "first frame should be sent")
                try expect(!filter.shouldSend(firstFrame), "identical frame should not be sent again")
                try expect(filter.shouldSend(Data([0x01, 0x02, 0x04])), "changed frame should be sent")
            }
        ),
        TestCase(
            name: "screen frame filter sends current frame after reset",
            run: {
                var filter = ScreenShareFrameChangeFilter()
                let frame = Data([0x10, 0x20])

                try expect(filter.shouldSend(frame), "first frame should be sent")
                try expect(!filter.shouldSend(frame), "unchanged frame should be suppressed")
                filter.reset()
                try expect(filter.shouldSend(frame), "frame should be sent after sharing restarts")
            }
        ),
    ]
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
    print("========== NotchScreenShareTests summary ==========")
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

let exitCode = runAll()
exit(Int32(exitCode))

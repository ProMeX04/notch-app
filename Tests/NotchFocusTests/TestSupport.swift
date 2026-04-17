import Foundation

enum FocusTestError: Error, CustomStringConvertible {
    case assertion(String, file: StaticString, line: UInt)

    var description: String {
        switch self {
        case let .assertion(message, file, line):
            return "\(file):\(line): \(message)"
        }
    }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "expectation failed",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if !condition() {
        throw FocusTestError.assertion(message(), file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let left = lhs()
    let right = rhs()
    if left != right {
        let extra = message().isEmpty ? "" : " — \(message())"
        throw FocusTestError.assertion(
            "expected \(right), got \(left)\(extra)",
            file: file,
            line: line
        )
    }
}

func makeIsolatedUserDefaults(label: String) -> UserDefaults {
    let suiteName = "NotchFocusTests.\(label).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
final class TestPomodoroClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

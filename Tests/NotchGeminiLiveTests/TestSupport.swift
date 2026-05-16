import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(message: message) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(message: "\(message) — expected \(expected), got \(actual)")
    }
}

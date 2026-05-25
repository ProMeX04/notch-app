import Foundation

enum ShelfTestError: Error, CustomStringConvertible {
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
        throw ShelfTestError.assertion(message(), file: file, line: line)
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
        throw ShelfTestError.assertion(
            "expected \(right), got \(left)\(extra)",
            file: file,
            line: line
        )
    }
}

func expectUnwrapped<T>(
    _ value: @autoclosure () -> T?,
    _ message: @autoclosure () -> String = "expected non-nil value",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let unwrapped = value() else {
        throw ShelfTestError.assertion(message(), file: file, line: line)
    }
    return unwrapped
}

func makeTempDirectory(label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func cleanupDirectory(_ url: URL?) {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
}

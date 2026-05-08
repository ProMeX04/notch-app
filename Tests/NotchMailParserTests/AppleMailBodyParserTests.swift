import Foundation
import NotchMailParserCore

@main
struct AppleMailBodyParserTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("parses valid emlx byte-count wrapper", testParsesValidEMLXByteCountWrapper),
            ("invalid emlx byte-count fails safely", testInvalidEMLXByteCountFailsSafely),
            ("truncated emlx payload fails safely", testTruncatedEMLXPayloadFailsSafely),
            ("parses plain text RFC822", testParsesPlainTextRFC822),
            ("multipart alternative uses plain text part", testMultipartAlternativeUsesPlainTextPart),
            ("HTML-only message falls back to text", testHTMLOnlyMessageFallsBackToText),
            ("decodes base64 body", testDecodesBase64Body),
            ("decodes quoted-printable body", testDecodesQuotedPrintableBody),
            ("ignores attachment parts", testIgnoresAttachmentParts),
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
        }

        if failures > 0 {
            print("\(failures) mail parser test(s) failed")
            exit(1)
        }
        print("All \(tests.count) mail parser tests passed")
    }

    static func testParsesValidEMLXByteCountWrapper() throws {
        let rfc822 = """
        From: sender@example.com
        Content-Type: text/plain; charset=utf-8

        Hello from emlx.
        """
        let emlx = emlxData(wrapping: rfc822, trailing: "<?xml version=\"1.0\"?>")

        try expectEqual(AppleMailBodyParser.parseEMLX(emlx), "Hello from emlx.")
    }

    static func testInvalidEMLXByteCountFailsSafely() throws {
        let data = Data("not-a-number\nContent-Type: text/plain\n\nBody".utf8)

        try expectNil(AppleMailBodyParser.parseEMLX(data))
    }

    static func testTruncatedEMLXPayloadFailsSafely() throws {
        let data = Data("100\nContent-Type: text/plain\n\nShort".utf8)

        try expectNil(AppleMailBodyParser.parseEMLX(data))
    }

    static func testParsesPlainTextRFC822() throws {
        let rfc822 = """
        Content-Type: text/plain; charset=utf-8

        First line.

        Second line.
        """

        try expectEqual(AppleMailBodyParser.parseRFC822(Data(rfc822.utf8)), "First line.\n\nSecond line.")
    }

    static func testMultipartAlternativeUsesPlainTextPart() throws {
        let rfc822 = """
        Content-Type: multipart/alternative; boundary="abc"

        --abc
        Content-Type: text/plain; charset=utf-8

        Plain body.
        --abc
        Content-Type: text/html; charset=utf-8

        <html><body><p>HTML body.</p></body></html>
        --abc--
        """

        try expectEqual(AppleMailBodyParser.parseRFC822(Data(rfc822.utf8)), "Plain body.")
    }

    static func testHTMLOnlyMessageFallsBackToText() throws {
        let rfc822 = """
        Content-Type: text/html; charset=utf-8

        <html><body><p>Hello <b>HTML</b>.</p><p>Second.</p></body></html>
        """
        let body = AppleMailBodyParser.parseRFC822(Data(rfc822.utf8))

        try expect(body?.contains("Hello HTML.") == true, "Expected HTML text body, got \(body ?? "nil")")
        try expect(body?.contains("Second.") == true, "Expected second paragraph, got \(body ?? "nil")")
    }

    static func testDecodesBase64Body() throws {
        let encoded = Data("Base64 body.".utf8).base64EncodedString()
        let rfc822 = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        \(encoded)
        """

        try expectEqual(AppleMailBodyParser.parseRFC822(Data(rfc822.utf8)), "Base64 body.")
    }

    static func testDecodesQuotedPrintableBody() throws {
        let rfc822 = """
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Hello=20quoted=2Dprintable=
         body.
        """

        try expectEqual(AppleMailBodyParser.parseRFC822(Data(rfc822.utf8)), "Hello quoted-printable body.")
    }

    static func testIgnoresAttachmentParts() throws {
        let rfc822 = """
        Content-Type: multipart/mixed; boundary="mix"

        --mix
        Content-Type: application/octet-stream
        Content-Disposition: attachment; filename="secret.txt"

        Attachment body should be ignored.
        --mix
        Content-Type: text/plain; charset=utf-8

        Real message body.
        --mix--
        """

        try expectEqual(AppleMailBodyParser.parseRFC822(Data(rfc822.utf8)), "Real message body.")
    }

    static func emlxData(wrapping rfc822: String, trailing: String = "") -> Data {
        var data = Data()
        let payload = Data(rfc822.utf8)
        data.append(Data("\(payload.count)\n".utf8))
        data.append(payload)
        data.append(Data(trailing.utf8))
        return data
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(message) }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected { throw TestFailure("Expected \(expected), got \(actual)") }
    }

    static func expectNil<T>(_ actual: T?) throws {
        if let actual { throw TestFailure("Expected nil, got \(actual)") }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

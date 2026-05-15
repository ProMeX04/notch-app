import Foundation
import NotchFocusCore

// MARK: - DurationParser Tests

enum DurationParserTests {

    // MARK: Unit format - seconds

    static func unitSeconds_s() throws {
        try expectEqual(DurationParser.parse("30s"), 30)
        try expectEqual(DurationParser.parse("90s"), 90)
        try expectEqual(DurationParser.parse("0s"), nil)
    }

    static func unitSeconds_sec() throws {
        try expectEqual(DurationParser.parse("45sec"), 45)
        try expectEqual(DurationParser.parse("120sec"), 120)
    }

    static func unitSeconds_secs() throws {
        try expectEqual(DurationParser.parse("10secs"), 10)
    }

    static func unitSeconds_second() throws {
        try expectEqual(DurationParser.parse("5second"), 5)
    }

    static func unitSeconds_seconds() throws {
        try expectEqual(DurationParser.parse("15seconds"), 15)
    }

    static func unitSeconds_minute() throws {
        try expectEqual(DurationParser.parse("3min"), 180)
        try expectEqual(DurationParser.parse("2min"), 120)
    }

    static func unitSeconds_mins() throws {
        try expectEqual(DurationParser.parse("10mins"), 600)
    }

    static func unitSeconds_minuteFull() throws {
        try expectEqual(DurationParser.parse("5minute"), 300)
    }

    static func unitSeconds_minutesFull() throws {
        try expectEqual(DurationParser.parse("7minutes"), 420)
    }

    static func unitSeconds_hour() throws {
        try expectEqual(DurationParser.parse("1h"), 3600)
        try expectEqual(DurationParser.parse("2h"), 7200)
    }

    static func unitSeconds_hr() throws {
        try expectEqual(DurationParser.parse("3hr"), 10800)
    }

    static func unitSeconds_hrs() throws {
        try expectEqual(DurationParser.parse("4hrs"), 14400)
    }

    static func unitSeconds_hourFull() throws {
        try expectEqual(DurationParser.parse("2hour"), 7200)
    }

    static func unitSeconds_hoursFull() throws {
        try expectEqual(DurationParser.parse("3hours"), 10800)
    }

    static func unitSeconds_day() throws {
        try expectEqual(DurationParser.parse("1d"), 86400)
        try expectEqual(DurationParser.parse("2d"), 172800)
    }

    static func unitSeconds_fractionalHour() throws {
        try expectEqual(DurationParser.parse("1.5h"), 5400)
        try expectEqual(DurationParser.parse("0.5h"), 1800)
    }

    // MARK: Combined units

    static func combinedUnits_hoursAndMinutes() throws {
        try expectEqual(DurationParser.parse("1h30m"), 5400)
        try expectEqual(DurationParser.parse("2h15m"), 8100)
    }

    static func combinedUnits_daysHoursMinutes() throws {
        try expectEqual(DurationParser.parse("1d 2h 30m"), 95400)
    }

    static func combinedUnits_noSpaces() throws {
        // \s* allows zero whitespace, so 1d2h parses as 1d + 2h = 93600
        try expectEqual(DurationParser.parse("1d2h"), 93600)
    }

    // MARK: Colon format - legacy context

    static func colonFormat_legacyMMSS() throws {
        try expectEqual(DurationParser.parse("1:30"), 90)
        try expectEqual(DurationParser.parse("5:00"), 300)
    }

    static func colonFormat_legacyHMMS() throws {
        try expectEqual(DurationParser.parse("1:30:00"), 5400)
        try expectEqual(DurationParser.parse("2:15:30"), 8130)
    }

    static func colonFormat_legacySingleDigit() throws {
        try expectEqual(DurationParser.parse("1:05"), 65)
    }

    // MARK: Colon format - minutes scale context

    static func colonFormat_minutesScaleHM() throws {
        // 2:05 with minutesScale = 2 hours, 5 minutes = 125 minutes = 7500 seconds
        try expectEqual(
            DurationParser.parse("1:30", colonContext: .minutesScale),
            5400
        )
        try expectEqual(
            DurationParser.parse("2:05", colonContext: .minutesScale),
            7500
        )
    }

    static func colonFormat_minutesScaleEdgeCases() throws {
        try expectEqual(
            DurationParser.parse("0:00", colonContext: .minutesScale),
            0
        )
        try expectEqual(
            DurationParser.parse("23:59", colonContext: .minutesScale),
            86340
        )
    }

    static func colonFormat_minutesScaleRejectsInvalidHour() throws {
        try expectEqual(
            DurationParser.parse("24:00", colonContext: .minutesScale),
            1440
        )
        try expectEqual(
            DurationParser.parse("99:30", colonContext: .minutesScale),
            5970
        )
    }

    // MARK: Plain number

    static func plainNumber_treatedAsMinutes() throws {
        try expectEqual(DurationParser.parse("25"), 1500)
        try expectEqual(DurationParser.parse("5"), 300)
        try expectEqual(DurationParser.parse("1"), 60)
    }

    static func plainNumber_fractional() throws {
        try expectEqual(DurationParser.parse("1.5"), 90)
        try expectEqual(DurationParser.parse("0.5"), 30)
    }

    static func plainNumber_withCommaDecimal() throws {
        try expectEqual(DurationParser.parse("1,5"), 90)
    }

    // MARK: Edge cases

    static func emptyString_returnsNil() throws {
        try expectEqual(DurationParser.parse(""), nil)
        try expectEqual(DurationParser.parse("   "), nil)
    }

    static func whitespaceOnly_returnsNil() throws {
        try expectEqual(DurationParser.parse("  "), nil)
        try expectEqual(DurationParser.parse("\t"), nil)
    }

    static func caseInsensitive() throws {
        try expectEqual(DurationParser.parse("30S"), 30)
        try expectEqual(DurationParser.parse("1H30M"), 5400)
        try expectEqual(DurationParser.parse("2D"), 172800)
    }

    static func noMatch_returnsNil() throws {
        try expectEqual(DurationParser.parse("abc"), nil)
        try expectEqual(DurationParser.parse("hello world"), nil)
    }

    static func leadingTrailingWhitespace() throws {
        try expectEqual(DurationParser.parse("  30m  "), 1800)
        try expectEqual(DurationParser.parse("\t1h\t"), 3600)
    }

    // MARK: Display string

    static func displayString_secondsOnly() throws {
        try expectEqual(DurationParser.displayString(for: 45), "45s")
        try expectEqual(DurationParser.displayString(for: 0), "0s")
    }

    static func displayString_minutesAndSeconds() throws {
        try expectEqual(DurationParser.displayString(for: 90), "1m 30s")
        try expectEqual(DurationParser.displayString(for: 125), "2m 5s")
    }

    static func displayString_hoursMinutesSeconds() throws {
        try expectEqual(DurationParser.displayString(for: 3665), "1h 1m 5s")
    }

    static func displayString_days() throws {
        try expectEqual(DurationParser.displayString(for: 90000), "1d 1h")
        try expectEqual(DurationParser.displayString(for: 86400), "1d")
    }

    static func displayString_noTrailingZeroSeconds() throws {
        try expectEqual(DurationParser.displayString(for: 120), "2m")
        try expectEqual(DurationParser.displayString(for: 7200), "2h")
    }
}

// MARK: - Test helpers

// MARK: - Test helpers

private func expectEqual(_ actual: Int?, _ expected: Int?, _ message: String = "") throws {
    guard actual == expected else {
        throw FocusTestError.assertion("expected \(String(describing: expected)), got \(String(describing: actual)) — \(message)", file: #filePath, line: #line)
    }
}
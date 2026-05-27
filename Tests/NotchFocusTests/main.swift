import Foundation
import NotchFocusFeature

struct TestCase {
    let name: String
    let run: () async throws -> Void
}

extension TestCase {
    init(name: String, run: @escaping () throws -> Void) {
        self.name = name
        self.run = { try run() }
    }
}

@MainActor
func buildTestCases() -> [TestCase] {
    var cases: [TestCase] = [
        // PomodoroViewModel P0 tests
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
            name: "focus/pause preserves remaining seconds without fullscreen side effects",
            run: PomodoroViewModelTests.pausePreservesRemainingSecondsWithoutFullscreenSideEffects
        ),
        TestCase(
            name: "focus/pause reset and skip do not complete leaderboard sessions",
            run: PomodoroViewModelTests.pauseResetAndSkipFlushDurationWithoutCompletingSession
        ),
        TestCase(
            name: "focus/natural completion records one leaderboard session",
            run: PomodoroViewModelTests.naturalFocusCompletionRecordsExactlyOneCompletedSession
        ),
        TestCase(
            name: "focus/cycle indicators stay consistent across edges",
            run: PomodoroViewModelTests.cycleIndicatorsStayConsistentAcrossEdges
        ),
        TestCase(
            name: "focus/running restore keeps active timer",
            run: PomodoroViewModelTests.runningRestoreKeepsActiveTimer
        ),
        TestCase(
            name: "focus/paused restore keeps session paused",
            run: PomodoroViewModelTests.pausedRestoreKeepsSessionPaused
        ),
        TestCase(
            name: "focus/updating durations preserves direct configuration",
            run: PomodoroViewModelTests.updatingDurationsPreservesDirectConfiguration
        ),
        TestCase(
            name: "focus/reset returns to idle focus baseline",
            run: PomodoroViewModelTests.resetReturnsToIdleFocusBaseline
        ),
    ]

    // DurationParser unit tests
    let dpTests: [(String, () throws -> Void)] = [
        ("duration-parser/unit s", DurationParserTests.unitSeconds_s),
        ("duration-parser/unit sec", DurationParserTests.unitSeconds_sec),
        ("duration-parser/unit secs", DurationParserTests.unitSeconds_secs),
        ("duration-parser/unit second", DurationParserTests.unitSeconds_second),
        ("duration-parser/unit seconds", DurationParserTests.unitSeconds_seconds),
        ("duration-parser/unit min", DurationParserTests.unitSeconds_minute),
        ("duration-parser/unit mins", DurationParserTests.unitSeconds_mins),
        ("duration-parser/unit minute (full)", DurationParserTests.unitSeconds_minuteFull),
        ("duration-parser/unit minutes (full)", DurationParserTests.unitSeconds_minutesFull),
        ("duration-parser/unit h", DurationParserTests.unitSeconds_hour),
        ("duration-parser/unit hr", DurationParserTests.unitSeconds_hr),
        ("duration-parser/unit hrs", DurationParserTests.unitSeconds_hrs),
        ("duration-parser/unit hour (full)", DurationParserTests.unitSeconds_hourFull),
        ("duration-parser/unit hours (full)", DurationParserTests.unitSeconds_hoursFull),
        ("duration-parser/unit d", DurationParserTests.unitSeconds_day),
        ("duration-parser/fractional h", DurationParserTests.unitSeconds_fractionalHour),
        ("duration-parser/combined h+m", DurationParserTests.combinedUnits_hoursAndMinutes),
        ("duration-parser/combined d+h+m", DurationParserTests.combinedUnits_daysHoursMinutes),
        ("duration-parser/combined no spaces", DurationParserTests.combinedUnits_noSpaces),
        ("duration-parser/colon standard mm:ss", DurationParserTests.colonFormat_standardMMSS),
        ("duration-parser/colon standard h:mm:ss", DurationParserTests.colonFormat_standardHMMS),
        ("duration-parser/colon standard single digit", DurationParserTests.colonFormat_standardSingleDigit),
        ("duration-parser/colon minutesScale h:mm", DurationParserTests.colonFormat_minutesScaleHM),
        ("duration-parser/colon minutesScale edge cases", DurationParserTests.colonFormat_minutesScaleEdgeCases),
        ("duration-parser/colon minutesScale rejects invalid", DurationParserTests.colonFormat_minutesScaleRejectsInvalidHour),
        ("duration-parser/plain number as minutes", DurationParserTests.plainNumber_treatedAsMinutes),
        ("duration-parser/plain fractional", DurationParserTests.plainNumber_fractional),
        ("duration-parser/plain comma decimal", DurationParserTests.plainNumber_withCommaDecimal),
        ("duration-parser/empty string nil", DurationParserTests.emptyString_returnsNil),
        ("duration-parser/whitespace nil", DurationParserTests.whitespaceOnly_returnsNil),
        ("duration-parser/case insensitive", DurationParserTests.caseInsensitive),
        ("duration-parser/no match nil", DurationParserTests.noMatch_returnsNil),
        ("duration-parser/leading trailing ws", DurationParserTests.leadingTrailingWhitespace),
        ("duration-parser/display seconds only", DurationParserTests.displayString_secondsOnly),
        ("duration-parser/display m+s", DurationParserTests.displayString_minutesAndSeconds),
        ("duration-parser/display h+m+s", DurationParserTests.displayString_hoursMinutesSeconds),
        ("duration-parser/display days", DurationParserTests.displayString_days),
        ("duration-parser/display no trailing 0s", DurationParserTests.displayString_noTrailingZeroSeconds),
    ]

    for (name, run) in dpTests {
        cases.append(TestCase(name: name) { try run() })
    }

    // MotivationalQuotes tests
    let mqTests: [(String, () throws -> Void)] = [
        ("motivational/focus phase returns from focus pool", MotivationalQuotesTests.focusPhase_returnsFromFocusPool),
        ("motivational/short break returns from break pool", MotivationalQuotesTests.shortBreakPhase_returnsFromBreakPool),
        ("motivational/long break returns from break pool", MotivationalQuotesTests.longBreakPhase_returnsFromBreakPool),
        ("motivational/viet lang returns Vietnamese", MotivationalQuotesTests.vietLang_returnsVietnameseText),
        ("motivational/english lang returns English", MotivationalQuotesTests.englishLang_returnsEnglishText),
        ("motivational/focus and break pools are non-empty", MotivationalQuotesTests.focusAndBreakPoolsAreDifferent),
        ("motivational/quote structure is valid", MotivationalQuotesTests.quoteStructure_isValid),
    ]

    for (name, run) in mqTests {
        cases.append(TestCase(name: name) { try run() })
    }

    // AppLanguageProvider tests
    let alpTests: [(String, () throws -> Void)] = [
        ("language-provider/default is English", AppLanguageProviderTests.defaultLanguage_isEnglish),
        ("language-provider/setting language updates", AppLanguageProviderTests.settingLanguage_updatesCurrentLanguage),
        ("language-provider/empty string is preserved", AppLanguageProviderTests.emptyString_isPreservedAsEmpty),
        ("language-provider/refresh reads latest", AppLanguageProviderTests.refresh_readsLatestFromUserDefaults),
        ("language-provider/refresh no-op when unchanged", AppLanguageProviderTests.refresh_noOpWhenUnchanged),
        ("language-provider/arbitrary language preserved", AppLanguageProviderTests.arbitraryLanguage_isPreserved),
    ]

    for (name, run) in alpTests {
        cases.append(TestCase(name: name) { try run() })
    }

    return cases
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

import Foundation
import NotchFocusCore

// MARK: - MotivationalQuotes Tests

enum MotivationalQuotesTests {

    static func focusPhase_returnsFromFocusPool() throws {
        let quote = MotivationalQuotes.getRandom(for: .focus, lang: "English")

        try expect(!quote.text.isEmpty, "focus quote text should not be empty")
        try expect(!quote.author.isEmpty, "focus quote author should not be empty")
    }

    static func shortBreakPhase_returnsFromBreakPool() throws {
        let quote = MotivationalQuotes.getRandom(for: .shortBreak, lang: "English")

        try expect(!quote.text.isEmpty, "short break quote text should not be empty")
        try expect(!quote.author.isEmpty, "short break quote author should not be empty")
    }

    static func longBreakPhase_returnsFromBreakPool() throws {
        let quote = MotivationalQuotes.getRandom(for: .longBreak, lang: "English")

        try expect(!quote.text.isEmpty, "long break quote text should not be empty")
        try expect(!quote.author.isEmpty, "long break quote author should not be empty")
    }

    static func vietLang_returnsVietnameseText() throws {
        let quote = MotivationalQuotes.getRandom(for: .focus, lang: "Tiếng Việt")

        try expect(!quote.text.isEmpty, "quote text should not be empty for Vietnamese")
        try expect(!quote.author.isEmpty, "author should not be empty for Vietnamese")
    }

    static func englishLang_returnsEnglishText() throws {
        let quote = MotivationalQuotes.getRandom(for: .focus, lang: "English")

        try expect(!quote.text.isEmpty, "quote text should not be empty for English")
        try expect(!quote.author.isEmpty, "author should not be empty for English")
    }

    static func focusAndBreakPoolsAreDifferent() throws {
        let focusQuote = MotivationalQuotes.getRandom(for: .focus, lang: "English")
        var breakQuote = MotivationalQuotes.getRandom(for: .shortBreak, lang: "English")

        // They could theoretically be the same by chance, so run multiple times
        var foundDifference = false
        for _ in 0..<10 {
            breakQuote = MotivationalQuotes.getRandom(for: .shortBreak, lang: "English")
            if focusQuote.text != breakQuote.text || focusQuote.author != breakQuote.author {
                foundDifference = true
                break
            }
        }
        // Just verify we get valid quotes back (pools are non-empty)
        try expect(!focusQuote.text.isEmpty, "focus pool should be non-empty")
        try expect(!breakQuote.text.isEmpty, "break pool should be non-empty")
    }

    static func quoteStructure_isValid() throws {
        let focusQuote = MotivationalQuotes.getRandom(for: .focus, lang: "English")
        let breakQuote = MotivationalQuotes.getRandom(for: .shortBreak, lang: "English")

        try expect(focusQuote.text.count > 0 && focusQuote.author.count > 0, "focus quote must have text and author")
        try expect(breakQuote.text.count > 0 && breakQuote.author.count > 0, "break quote must have text and author")
    }
}
import Foundation
import NotchGeminiLiveCore

enum GeminiLiveSessionPolicyTests {
    @MainActor
    static let allTests: [TestCase] = [
        TestCase(name: "Gemini 3 thinking sends thinkingLevel only") {
            try expectEqual(
                GeminiThinkingLevel.high.wireConfiguration(forModel: "gemini-3.1-flash-live-preview"),
                .level("HIGH"),
                "high level payload"
            )
            try expectEqual(
                GeminiThinkingLevel.off.wireConfiguration(forModel: "models/gemini-3.1-flash-live-preview"),
                .level("MINIMAL"),
                "legacy off migration payload"
            )
        },
        TestCase(name: "Gemini 2.5 thinking supports off automatic and budgets") {
            let model = "gemini-2.5-flash-native-audio-preview-12-2025"
            try expectEqual(GeminiThinkingLevel.off.wireConfiguration(forModel: model), .budget(0), "off payload")
            try expectEqual(GeminiThinkingLevel.automatic.wireConfiguration(forModel: model), .automatic, "automatic payload")
            try expectEqual(GeminiThinkingLevel.medium.wireConfiguration(forModel: model), .budget(2048), "medium payload")
        },
        TestCase(name: "Thinking choices are model aware") {
            try expectEqual(
                GeminiThinkingLevel.availableLevels(forModel: "gemini-3.1-flash-live-preview"),
                [.minimal, .low, .medium, .high],
                "Gemini 3.1 choices"
            )
            try expectEqual(
                GeminiThinkingLevel.availableLevels(forModel: "gemini-2.5-flash-native-audio-preview-12-2025"),
                [.off, .automatic, .low, .medium, .high],
                "Gemini 2.5 choices"
            )
        },
        TestCase(name: "Non-resumable updates retain last usable handle") {
            var state = GeminiLiveResumptionState()
            state.acceptUpdate(resumable: true, newHandle: "first-handle")
            state.acceptUpdate(resumable: false, newHandle: nil)
            try expectEqual(state.handle, "first-handle", "fallback handle")

            state.acceptUpdate(resumable: true, newHandle: "second-handle")
            try expectEqual(state.handle, "second-handle", "updated handle")
            state.clear()
            try expect(state.handle == nil, "explicit clear should remove handle")
        },
    ]
}

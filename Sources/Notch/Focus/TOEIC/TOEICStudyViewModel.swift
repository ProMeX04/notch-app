import Combine
import Foundation
import NotchFocusFeature

@MainActor
final class TOEICStudyViewModel: ObservableObject {
    static let shared = TOEICStudyViewModel()

    /// How many AI questions to keep ready / generate per batch.
    static let autoQuizBatchSize = 5
    /// Prefetch more when this many unanswered AI items remain.
    static let autoQuizPrefetchThreshold = 2

    @Published var mode: TOEICStudyMode = .flashcards
    @Published private(set) var deck: [TOEICVocabCard] = []
    @Published private(set) var cardIndex: Int = 0
    @Published var isFlipped: Bool = false

    @Published private(set) var quizDeck: [TOEICQuizItem] = []
    @Published private(set) var quizIndex: Int = 0
    @Published var selectedChoice: Int?
    @Published var didRevealAnswer: Bool = false
    @Published var liveExplanation: String?
    /// Subtitle under the stem after answer (VI translation, or filled English fallback while loading).
    @Published var liveTranslation: String?

    @Published private(set) var sessionCorrect: Int = 0
    @Published private(set) var sessionAnswered: Int = 0
    /// Consecutive correct answers in the current quiz session (resets on wrong).
    @Published private(set) var quizStreak: Int = 0
    /// Minutes granted by the last study action (for UI flash).
    @Published private(set) var lastLeisureRewardMinutes: Int = 0

    @Published private(set) var isGenerating = false
    @Published var statusMessage: String?

    /// Optional Focus timer — when set, leisure minutes can extend breaks.
    weak var pomodoro: PomodoroViewModel?
    @Published private(set) var usingAIContent = false
    @Published private(set) var bankWordCount: Int = 0
    /// Live IPA for the current card (from bank field, cache, or API).
    @Published private(set) var currentPhonetic: String = ""

    let progress: TOEICProgressStore
    let speech = TOEICSpeechPlayer.shared
    let phonetics = TOEICPhoneticService.shared

    private var autoQuizTask: Task<Void, Never>?
    private var recentAIPrompts: [String] = []

    private init(progress: TOEICProgressStore = .shared) {
        self.progress = progress
        bankWordCount = TOEICCatalog.wordBank.count
        statusMessage = nil
        rebuildDecks(shuffle: true)
    }

    func reloadBank() {
        bankWordCount = TOEICCatalog.wordBank.count
        statusMessage = nil
        rebuildDecks(shuffle: true)
    }

    /// IPA line for UI (slash-wrapped when available).
    var displayPhonetic: String {
        if !currentPhonetic.isEmpty { return currentPhonetic }
        return currentCard.map { phonetics.phonetic(for: $0) } ?? ""
    }

    func speakCurrentWord(autoFetchIPA: Bool = true) {
        guard let card = currentCard else { return }
        speech.speak(card.word)
        // IPA is bundled offline — just refresh the displayed string.
        if autoFetchIPA {
            syncPhoneticForCurrentCard()
        }
    }

    func refreshPhoneticForCurrentCard() async {
        syncPhoneticForCurrentCard()
    }

    private func syncPhoneticForCurrentCard() {
        guard let card = currentCard else {
            currentPhonetic = ""
            return
        }
        // From toeic_vocabulary.pronunciation + toeic_phonetics.json (no runtime AI).
        currentPhonetic = phonetics.phonetic(for: card)
    }

    var currentCard: TOEICVocabCard? {
        guard deck.indices.contains(cardIndex) else { return nil }
        return deck[cardIndex]
    }

    var currentQuiz: TOEICQuizItem? {
        guard quizDeck.indices.contains(quizIndex) else { return nil }
        return quizDeck[quizIndex]
    }

    var cardProgressLabel: String {
        guard !deck.isEmpty else { return "0/0" }
        return "\(cardIndex + 1)/\(deck.count)"
    }

    var quizProgressLabel: String {
        guard !quizDeck.isEmpty else { return "0/0" }
        return "\(quizIndex + 1)/\(quizDeck.count)"
    }

    var sessionAccuracyLabel: String {
        guard sessionAnswered > 0 else { return "—" }
        let pct = Int((Double(sessionCorrect) / Double(sessionAnswered) * 100).rounded())
        return "\(pct)%"
    }

    var contentSourceLabelKey: String {
        usingAIContent ? "AI quiz · auto" : "Vocab fallback · offline"
    }

    var aiQuizCount: Int {
        quizDeck.filter { $0.id.hasPrefix("ext-ai-") }.count
    }

    // MARK: - Decks

    func rebuildDecks(shuffle: Bool) {
        let known = Set(progress.snapshot.knownCardIDs)
        bankWordCount = TOEICCatalog.wordBank.count

        var cards = TOEICCatalog.drawVocab(
            count: min(50, max(bankWordCount, 1)),
            knownIDs: known
        )
        if cards.isEmpty {
            cards = TOEICCatalog.seedVocab
        }

        // Short meaning placeholders only — real Part 5 stems come from auto AI gen.
        var quiz = TOEICCatalog.offlineQuizDeck(
            vocabCards: Array(cards),
            limit: Self.autoQuizBatchSize
        )

        if shuffle {
            cards.shuffle()
            quiz.shuffle()
        } else {
            cards.sort { a, b in
                let ak = known.contains(a.id)
                let bk = known.contains(b.id)
                if ak == bk { return false }
                return !ak && bk
            }
        }

        deck = Array(cards.prefix(50))
        quizDeck = Array(quiz.prefix(Self.autoQuizBatchSize))
        cardIndex = 0
        quizIndex = 0
        isFlipped = false
        selectedChoice = nil
        didRevealAnswer = false
        liveExplanation = nil
        liveTranslation = nil
        sessionCorrect = 0
        sessionAnswered = 0
        quizStreak = 0
        usingAIContent = false
        syncPhoneticForCurrentCard()

        // Warm AI quiz pool in background.
        scheduleAutoAIQuiz(replace: true, switchToQuiz: false)
    }

    /// Call when user switches to Quiz tab — ensures AI stems are generating.
    func onEnterQuizMode() {
        if aiQuizCount == 0 {
            scheduleAutoAIQuiz(replace: true, switchToQuiz: false)
        } else {
            schedulePrefetchIfNeeded()
        }
    }

    func flipCard() {
        isFlipped.toggle()
        if isFlipped, let id = currentCard?.id {
            progress.markReviewed(cardID: id)
        }
    }

    func markCurrentKnown(_ known: Bool) {
        guard let id = currentCard?.id else { return }
        progress.markKnown(cardID: id, known: known)
        if known {
            creditLeisure(TOEICLeisureRewards.minutesPerKnownCard)
        } else {
            lastLeisureRewardMinutes = 0
        }
        nextCard()
    }

    func nextCard() {
        guard !deck.isEmpty else { return }
        isFlipped = false
        if cardIndex + 1 < deck.count {
            cardIndex += 1
        } else {
            progress.completeSession()
            deck.shuffle()
            cardIndex = 0
        }
        syncPhoneticForCurrentCard()
    }

    func previousCard() {
        guard cardIndex > 0 else { return }
        isFlipped = false
        cardIndex -= 1
        syncPhoneticForCurrentCard()
    }

    func selectChoice(_ index: Int) {
        guard !didRevealAnswer, let item = currentQuiz else { return }
        selectedChoice = index
        didRevealAnswer = true
        liveExplanation = nil
        liveTranslation = TOEICQuizText.lineUnderQuestion(for: item)
        let correct = index == item.correctIndex
        sessionAnswered += 1
        if correct {
            sessionCorrect += 1
            quizStreak += 1
            creditLeisure(TOEICLeisureRewards.minutesForCorrectQuiz(streakAfterCorrect: quizStreak))
        } else {
            quizStreak = 0
            lastLeisureRewardMinutes = 0
        }
        progress.recordQuiz(correct: correct)

        let hasVI = !item.translationVI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !TOEICQuizText.splitExplanationAndTranslation(
                explanation: item.explanationVI,
                translation: ""
            ).translation.isEmpty
        if !hasVI, TOEICQuizText.completedSentence(
            prompt: item.prompt,
            answer: item.choices.indices.contains(item.correctIndex) ? item.choices[item.correctIndex] : ""
        ) != nil {
            Task { await fillMissingTranslation(for: item) }
        }
    }

    func nextQuiz() {
        guard !quizDeck.isEmpty else { return }
        selectedChoice = nil
        didRevealAnswer = false
        liveExplanation = nil
        liveTranslation = nil
        if quizIndex + 1 < quizDeck.count {
            quizIndex += 1
        } else {
            progress.completeSession()
            // End of deck — generate a fresh AI batch instead of reshuffling offline.
            quizIndex = max(0, quizDeck.count - 1)
            scheduleAutoAIQuiz(replace: true, switchToQuiz: false)
        }
        schedulePrefetchIfNeeded()
    }

    /// Bank leisure minutes from study (shown in UI). Applied to Focus break when break starts.
    /// Also pushes a grant to Block Shorts & Reels (`gemini_pending_minutes` via bridge).
    private func creditLeisure(_ minutes: Int) {
        let granted = progress.earnLeisureMinutes(minutes)
        lastLeisureRewardMinutes = granted
        guard granted > 0 else { return }
        TOEICBlockShortsBridge.shared.enqueueLeisureMinutes(
            granted,
            reason: "study_reward"
        )
        TOEICBlockShortsBridge.shared.startServerIfNeeded()
        statusMessage = String(
            format: Localization.get("+%d min leisure"),
            granted
        )
    }

    /// Called when a Focus break begins — move banked minutes onto the break timer.
    func applyLeisureBankToBreak() {
        let minutes = progress.spendAllLeisureMinutes()
        guard minutes > 0 else { return }
        pomodoro?.grantLeisureBreakSeconds(minutes * 60)
        statusMessage = String(
            format: Localization.get("Break +%d min from study"),
            minutes
        )
    }

    private func fillMissingTranslation(for item: TOEICQuizItem) async {
        let answer = item.choices.indices.contains(item.correctIndex)
            ? item.choices[item.correctIndex]
            : ""
        guard let english = TOEICQuizText.completedSentence(prompt: item.prompt, answer: answer) else {
            return
        }
        do {
            let vi = try await TOEICAIGenerator.translateSentence(english)
            let cleaned = vi.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            if currentQuiz?.id == item.id, didRevealAnswer {
                liveTranslation = cleaned
            }
            if let idx = quizDeck.firstIndex(where: { $0.id == item.id }) {
                let old = quizDeck[idx]
                quizDeck[idx] = TOEICQuizItem(
                    id: old.id,
                    prompt: old.prompt,
                    choices: old.choices,
                    correctIndex: old.correctIndex,
                    explanationVI: old.explanationVI,
                    part: old.part,
                    translationVI: cleaned
                )
            }
        } catch {
            // Keep filled-English fallback.
        }
    }

    // MARK: - Auto AI quiz pipeline

    private func scheduleAutoAIQuiz(replace: Bool, switchToQuiz: Bool) {
        autoQuizTask?.cancel()
        autoQuizTask = Task { [weak self] in
            await self?.generateAIQuiz(
                count: Self.autoQuizBatchSize,
                replace: replace,
                switchToQuiz: switchToQuiz
            )
        }
    }

    private func schedulePrefetchIfNeeded() {
        let remaining = max(0, quizDeck.count - quizIndex - 1)
        let needMore = remaining <= Self.autoQuizPrefetchThreshold || aiQuizCount < Self.autoQuizBatchSize
        guard needMore, !isGenerating else { return }
        autoQuizTask = Task { [weak self] in
            await self?.generateAIQuiz(
                count: Self.autoQuizBatchSize,
                replace: false,
                switchToQuiz: false
            )
        }
    }

    /// AI-generated Part 5/6 from vocab seeds. Progressive: first stem replaces placeholders ASAP.
    /// - Parameters:
    ///   - replace: clear deck and session; otherwise append.
    ///   - switchToQuiz: jump UI to quiz tab (sparkles button).
    func generateAIQuiz(
        count: Int = TOEICStudyViewModel.autoQuizBatchSize,
        replace: Bool = true,
        switchToQuiz: Bool = true
    ) async {
        guard !isGenerating else { return }
        isGenerating = true
        statusMessage = Localization.get("Generating TOEIC Part 5/6…")
        defer {
            isGenerating = false
            if statusMessage?.contains("Generating") == true {
                statusMessage = nil
            }
        }

        let known = Set(progress.snapshot.knownCardIDs)
        let drawn = TOEICCatalog.drawVocab(count: count, knownIDs: known)
        guard !drawn.isEmpty else {
            statusMessage = Localization.get("Word bank is empty")
            return
        }

        let pool = TOEICCatalog.wordBank
        var exclude = recentAIPrompts
        if !replace {
            exclude.append(contentsOf: quizDeck.map(\.prompt))
        }

        if replace {
            selectedChoice = nil
            didRevealAnswer = false
            liveExplanation = nil
            liveTranslation = nil
            sessionCorrect = 0
            sessionAnswered = 0
            quizStreak = 0
            quizIndex = 0
            // Keep temporary offline placeholders until first AI item arrives.
            if quizDeck.isEmpty || usingAIContent {
                quizDeck = drawn.map { TOEICCatalog.offlineQuizItem(from: $0) }
                usingAIContent = false
            }
        }

        if switchToQuiz {
            mode = .quiz
        }

        var producedAI = 0
        let seedPool = (drawn + pool.shuffled().prefix(24))
        var seenSeedIDs = Set<String>()

        for focus in drawn {
            if Task.isCancelled { break }

            var seeds = [focus]
            for extra in seedPool where seeds.count < 5 {
                if extra.id == focus.id { continue }
                if seenSeedIDs.contains(extra.id) { continue }
                seeds.append(extra)
            }
            seenSeedIDs.insert(focus.id)

            do {
                let item = try await TOEICAIGenerator.generateOneExtensionStyleQuiz(
                    seeds: seeds,
                    excludeSentences: exclude,
                    focus: focus
                )
                if Task.isCancelled { break }

                producedAI += 1
                exclude.append(item.prompt)
                recentAIPrompts.append(item.prompt)
                if recentAIPrompts.count > 40 {
                    recentAIPrompts = Array(recentAIPrompts.suffix(40))
                }

                if replace && producedAI == 1 {
                    // First real stem: swap out meaning placeholders.
                    quizDeck = [item]
                    quizIndex = 0
                    selectedChoice = nil
                    didRevealAnswer = false
                    liveExplanation = nil
                    liveTranslation = nil
                    usingAIContent = true
                } else if replace {
                    quizDeck.append(item)
                } else {
                    // Prefetch: only append AI items (skip offline fillers).
                    quizDeck.append(item)
                    usingAIContent = true
                }

                statusMessage = String(
                    format: Localization.get("AI quiz: %d ready"),
                    aiQuizCount
                )
            } catch {
                // Skip failed stem; keep going (no static question bank).
                continue
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if producedAI == 0 {
            // Gateway down: keep meaning-based vocab quiz only.
            if replace || quizDeck.isEmpty {
                quizDeck = drawn.map { TOEICCatalog.offlineQuizItem(from: $0) }
                quizIndex = 0
                usingAIContent = false
            }
            statusMessage = Localization.get("AI unavailable · meaning quiz")
        } else if replace {
            statusMessage = String(
                format: Localization.get("AI Part 5/6: %d questions"),
                producedAI
            )
        }
    }

    func generateAIVocab(count: Int = 8) async {
        guard !isGenerating else { return }
        isGenerating = true
        statusMessage = Localization.get("Drawing from word bank…")
        defer { isGenerating = false }

        let known = Set(progress.snapshot.knownCardIDs)
        let drawn = TOEICCatalog.drawVocab(count: count, knownIDs: known)
        guard !drawn.isEmpty else {
            statusMessage = Localization.get("Word bank is empty")
            return
        }

        statusMessage = Localization.get("Refreshing examples…")
        let cards = (try? await TOEICAIGenerator.enhanceExamplesFromBank(cards: drawn)) ?? drawn

        deck = cards
        cardIndex = 0
        isFlipped = false
        usingAIContent = true
        mode = .flashcards
        statusMessage = String(
            format: Localization.get("Study set from bank: %d words"),
            cards.count
        )
        syncPhoneticForCurrentCard()
    }
}

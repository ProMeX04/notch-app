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
    /// Flashcard session size (due reviews + new cards via SRS).
    static let flashcardDeckSize = 12
    /// Quiz items per session (interleaved cloze + meaning).
    static let quizSessionSize = 20

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

    @Published var statusMessage: String?

    /// Optional Focus timer — when set, leisure minutes can extend breaks.
    weak var pomodoro: PomodoroViewModel?
    @Published private(set) var bankWordCount: Int = 0
    /// Live IPA for the current card (from bank field, cache, or API).
    @Published private(set) var currentPhonetic: String = ""

    let progress: TOEICProgressStore
    let speech = TOEICSpeechPlayer.shared
    let phonetics = TOEICPhoneticService.shared

    /// Words already used in this Focus study session (avoid immediate recycle).
    private var sessionSeenWordIDs: Set<String> = []
    /// Quiz item ids already answered/shown this session.
    private var sessionSeenQuizIDs: Set<String> = []

    private init(progress: TOEICProgressStore = .shared) {
        self.progress = progress
        bankWordCount = TOEICCatalog.wordBank.count
        statusMessage = nil
        rebuildDecks(shuffle: true)
    }

    func reloadBank() {
        bankWordCount = TOEICCatalog.wordBank.count
        statusMessage = nil
        sessionSeenWordIDs.removeAll()
        sessionSeenQuizIDs.removeAll()
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
        "SRS quiz · spaced + interleaved"
    }

    var prebuiltQuizCount: Int {
        quizDeck.filter {
            $0.id.hasPrefix("ai-cloze-")
                || $0.id.hasPrefix("ai-meaning-")
                || $0.id.hasPrefix("cloze-")
                || $0.id.hasPrefix("meaning-")
        }.count
    }

    /// Due reviews waiting (spaced repetition).
    var dueReviewCount: Int {
        progress.dueCount(in: TOEICCatalog.wordBank.map(\.id))
    }

    var newCardCount: Int {
        progress.newCount(in: TOEICCatalog.wordBank.map(\.id))
    }

    // MARK: - Decks

    func rebuildDecks(shuffle: Bool) {
        bankWordCount = TOEICCatalog.wordBank.count
        if shuffle {
            // Explicit refresh: allow previously seen session words again, but still SRS-order.
            sessionSeenWordIDs.removeAll()
            sessionSeenQuizIDs.removeAll()
        }

        let cards = drawNextSRSCardBatch(excluding: sessionSeenWordIDs)
        sessionSeenWordIDs.formUnion(cards.map(\.id))

        let quiz = makeQuizBatch(for: cards, excludeQuizIDs: sessionSeenQuizIDs)
        sessionSeenQuizIDs.formUnion(quiz.map(\.id))

        deck = cards
        quizDeck = quiz
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
        syncPhoneticForCurrentCard()
    }

    /// Next flashcard/word batch via SRS, skipping words already used this session when possible.
    private func drawNextSRSCardBatch(excluding: Set<String>) -> [TOEICVocabCard] {
        let schedules = progress.snapshot.cardSchedules
        let limit = min(Self.flashcardDeckSize, max(bankWordCount, 1))
        var cards = TOEICCatalog.drawVocabScheduled(
            count: limit,
            schedules: schedules,
            excludingIDs: excluding
        )
        // If we exhausted unseen words, allow recycle but still SRS-rank the full bank.
        if cards.count < max(4, limit / 2) {
            cards = TOEICCatalog.drawVocabScheduled(
                count: limit,
                schedules: schedules,
                excludingIDs: []
            )
        }
        if cards.isEmpty {
            cards = Array(TOEICCatalog.seedVocab.prefix(Self.flashcardDeckSize))
        }
        return cards
    }

    private func makeQuizBatch(
        for cards: [TOEICVocabCard],
        excludeQuizIDs: Set<String>
    ) -> [TOEICQuizItem] {
        let schedules = progress.snapshot.cardSchedules
        let known = Set(progress.snapshot.knownCardIDs)
        var batch = TOEICCatalog.quizDeckScheduled(
            for: cards,
            limit: Self.quizSessionSize,
            schedules: schedules,
            knownIDs: known
        )
        batch = batch.filter { !excludeQuizIDs.contains($0.id) }

        // Pad from global bank with unseen items if the word-set is too thin.
        if batch.count < Self.quizSessionSize {
            let pad = TOEICQuizBank.draw(
                limit: Self.quizSessionSize * 3,
                knownWordIDs: known
            ).filter { item in
                !excludeQuizIDs.contains(item.id) && !batch.contains(where: { $0.id == item.id })
            }
            batch.append(contentsOf: pad.prefix(Self.quizSessionSize - batch.count))
        }
        return Array(batch.prefix(Self.quizSessionSize))
    }

    /// Call when user switches to Quiz tab — top up from prebuilt bank if deck is short.
    func onEnterQuizMode() {
        if quizDeck.isEmpty {
            loadPrebuiltQuizDeck(replace: true)
        }
    }

    /// Map quiz item → vocab card id for SRS grading.
    static func cardID(forQuiz item: TOEICQuizItem) -> String? {
        let id = item.id
        let num: Int?
        if id.hasPrefix("ai-cloze-") {
            num = Int(id.dropFirst(9))
        } else if id.hasPrefix("ai-meaning-") {
            num = Int(id.dropFirst(11))
        } else if id.hasPrefix("cloze-") {
            num = Int(id.dropFirst(6))
        } else if id.hasPrefix("meaning-") {
            num = Int(id.dropFirst(8))
        } else {
            num = nil
        }
        guard let num else { return nil }
        return "vocab-\(num)"
    }

    func flipCard() {
        isFlipped.toggle()
        if isFlipped, let id = currentCard?.id {
            progress.markReviewed(cardID: id)
        }
    }

    func markCurrentKnown(_ known: Bool) {
        guard let id = currentCard?.id else { return }
        // Know → Good (interval expands); Again → lapse + relearn soon.
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
            // New SRS batch of words (not reshuffle the same 12 forever).
            let cards = drawNextSRSCardBatch(excluding: sessionSeenWordIDs)
            sessionSeenWordIDs.formUnion(cards.map(\.id))
            deck = cards
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
        sessionSeenQuizIDs.insert(item.id)
        if let wordID = Self.cardID(forQuiz: item) {
            sessionSeenWordIDs.insert(wordID)
        }

        let correct = index == item.correctIndex
        sessionAnswered += 1
        if correct {
            sessionCorrect += 1
            quizStreak += 1
            creditLeisure(TOEICLeisureRewards.minutesForCorrectQuiz(streakAfterCorrect: quizStreak))
        } else {
            quizStreak = 0
            lastLeisureRewardMinutes = 0
            // Successful relearning: one delayed retry later in this batch only.
            requeueFailedQuiz(item)
        }
        progress.recordQuiz(correct: correct, cardID: Self.cardID(forQuiz: item))
    }

    /// Insert a failed item ~3–5 slots later (once) — not forever looping.
    private func requeueFailedQuiz(_ item: TOEICQuizItem) {
        guard quizDeck.indices.contains(quizIndex) else { return }
        let remaining = quizDeck.suffix(from: min(quizIndex + 1, quizDeck.count))
        guard !remaining.contains(where: { $0.id == item.id }) else { return }
        let lag = min(max(0, quizDeck.count - quizIndex - 1), Int.random(in: 3...5))
        let insertAt = min(quizDeck.count, quizIndex + 1 + max(lag, 1))
        // Tag as a one-shot retry copy so we don't requeue endlessly by id match alone.
        quizDeck.insert(item, at: insertAt)
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
            // End of batch → advance to a NEW SRS word set (not the same 12 words).
            advanceToNextQuizBatch()
        }
    }

    /// After ~20 items: new words via SRS + new question ids (correct learning progression).
    private func advanceToNextQuizBatch() {
        let cards = drawNextSRSCardBatch(excluding: sessionSeenWordIDs)
        sessionSeenWordIDs.formUnion(cards.map(\.id))
        deck = cards
        cardIndex = 0

        let batch = makeQuizBatch(for: cards, excludeQuizIDs: sessionSeenQuizIDs)
        sessionSeenQuizIDs.formUnion(batch.map(\.id))

        guard !batch.isEmpty else {
            // True end of available unseen material this session — soft reset exclude list once.
            if !sessionSeenQuizIDs.isEmpty {
                sessionSeenQuizIDs.removeAll()
                sessionSeenWordIDs.removeAll()
                advanceToNextQuizBatch()
            }
            return
        }

        quizDeck = batch
        quizIndex = 0
        sessionCorrect = 0
        sessionAnswered = 0
        quizStreak = 0
        selectedChoice = nil
        didRevealAnswer = false
        liveExplanation = nil
        liveTranslation = nil
        statusMessage = String(
            format: Localization.get("Quiz ready: %d"),
            quizDeck.count
        )
    }

    /// Manual refresh (toolbar): new SRS words + new quiz batch.
    func loadPrebuiltQuizDeck(replace: Bool) {
        if replace {
            advanceToNextQuizBatch()
            mode = .quiz
            return
        }
        let cards = deck.isEmpty ? drawNextSRSCardBatch(excluding: sessionSeenWordIDs) : deck
        let batch = makeQuizBatch(for: cards, excludeQuizIDs: sessionSeenQuizIDs)
        sessionSeenQuizIDs.formUnion(batch.map(\.id))
        quizDeck.append(contentsOf: batch)
        statusMessage = String(
            format: Localization.get("Quiz ready: %d"),
            quizDeck.count
        )
    }

    /// Bank leisure minutes from study (shown in UI). Applied to Focus break when break starts.
    private func creditLeisure(_ minutes: Int) {
        let granted = progress.earnLeisureMinutes(minutes)
        lastLeisureRewardMinutes = granted
        guard granted > 0 else { return }
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

}

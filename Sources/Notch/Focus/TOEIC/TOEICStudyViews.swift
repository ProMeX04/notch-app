import SwiftUI

/// Clean, icon-first TOEIC study surface — minimal chrome, no filler copy.
struct TOEICStudyRootView: View {
    @ObservedObject private var vm = TOEICStudyViewModel.shared
    @ObservedObject private var progress = TOEICProgressStore.shared
    @AppStorage("app_language") private var appLanguage: String = "English"
    var tint: Color = .blue
    /// Hover question stem → swap to Vietnamese translation (after answer).
    @State private var isQuestionHovered = false

    private func L(_ key: String) -> String {
        Localization.get(key, lang: appLanguage)
    }

    /// Matches unified titlebar height so controls sit on the traffic-light row.
    private let titlebarRowHeight: CGFloat = 52

    var body: some View {
        // Fixed chrome + content shell — never rebuilds toolbar when mode flips.
        VStack(spacing: 0) {
            topBar
                .padding(.leading, 78) // room for red / yellow / green
                .padding(.trailing, 12)
                .frame(height: titlebarRowHeight)
                .frame(maxWidth: .infinity)
                .background(Color.black)

            Divider().overlay(Color.white.opacity(0.06))

            Group {
                switch vm.mode {
                case .flashcards:
                    flashcardsPane
                case .quiz:
                    quizPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        // Draw under the transparent titlebar so topBar shares its row.
        .ignoresSafeArea(.container, edges: .top)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            modeToggle
            compactStats
            Spacer(minLength: 0)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeIconButton(
                mode: .flashcards,
                systemName: "rectangle.on.rectangle.angled",
                help: L("Flashcards")
            )
            modeIconButton(
                mode: .quiz,
                systemName: "list.bullet.rectangle",
                help: L("Quiz")
            )
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func modeIconButton(mode: TOEICStudyMode, systemName: String, help: String) -> some View {
        let on = vm.mode == mode
        return Button {
            // No tree-wide animation: animating mode used to tear down the window toolbar.
            guard vm.mode != mode else { return }
            vm.mode = mode
            if mode == .quiz {
                vm.onEnterQuizMode()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? Color.black.opacity(0.85) : .white.opacity(0.55))
                .frame(width: 30, height: 24)
                .background {
                    if on {
                        Capsule().fill(tint)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Only surface stats that currently carry signal (hide zero placeholders).
    private var compactStats: some View {
        HStack(spacing: 12) {
            if vm.dueReviewCount > 0 {
                statIcon("calendar.badge.clock", "\(vm.dueReviewCount)", L("Due"), .orange)
            }

            let leisure = progress.snapshot.leisureMinutesBalance
            if leisure > 0 {
                statIcon("cup.and.saucer.fill", "\(leisure)m", L("Leisure"), .orange.opacity(0.9))
            }

            if vm.mode == .quiz {
                if vm.quizStreak > 0 {
                    statIcon("flame.fill", "\(vm.quizStreak)", L("Streak"), .orange.opacity(0.85))
                }
                if vm.sessionAnswered > 0 {
                    statIcon("target", vm.sessionAccuracyLabel, L("Accuracy"), tint.opacity(0.9))
                }
                // Progress in the current quiz batch.
                statIcon(
                    "list.number",
                    vm.quizProgressLabel,
                    L("Progress"),
                    .white.opacity(0.65)
                )
            } else if progress.snapshot.knownCount > 0 {
                statIcon(
                    "checkmark.circle.fill",
                    "\(progress.snapshot.knownCount)",
                    L("Known"),
                    tint
                )
            }
        }
    }

    private func statIcon(_ system: String, _ value: String, _ help: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color.opacity(0.9))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
        }
        .help(help)
    }

    // MARK: - Flashcards

    private var flashcardsPane: some View {
        VStack(spacing: 16) {
            if let card = vm.currentCard {
                ZStack(alignment: .topTrailing) {
                    Button(action: { vm.flipCard() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)

                            VStack(spacing: 14) {
                                if vm.isFlipped {
                                    if !card.part.isEmpty, card.part != "Word" {
                                        Text(card.part)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(tint.opacity(0.95))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(tint.opacity(0.14), in: Capsule())
                                    }
                                    Text(card.meaningVI)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.96))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !card.meaningEN.isEmpty, card.meaningEN != "Word" {
                                        Text(card.meaningEN)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.42))
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    phoneticRow(for: card)
                                    if !card.example.isEmpty {
                                        Text(card.example)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.38))
                                            .multilineTextAlignment(.center)
                                            .padding(.top, 4)
                                    }
                                } else {
                                    Text(card.word)
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.98))
                                    if !card.part.isEmpty, card.part != "Word" {
                                        Text(card.part)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    phoneticRow(for: card)
                                    Image(systemName: "hand.tap")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.18))
                                        .padding(.top, 4)
                                }
                            }
                            .padding(28)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Tap card to flip"))

                    // Speak sits outside the flip hit target.
                    speakButton
                        .padding(14)
                }
                .onChange(of: vm.cardIndex) { _, _ in
                    // Soft auto-speak when advancing cards (not on flip).
                }

                // No next/back — advance via Know / Again only.
                HStack(spacing: 12) {
                    roundAction(
                        systemName: "speaker.wave.2.fill",
                        help: L("Pronounce"),
                        tinted: false
                    ) { vm.speakCurrentWord() }

                    roundAction(
                        systemName: "arrow.counterclockwise",
                        help: L("Again"),
                        tinted: false
                    ) { vm.markCurrentKnown(false) }

                    roundAction(
                        systemName: "checkmark",
                        help: L("Know"),
                        tinted: true
                    ) { vm.markCurrentKnown(true) }
                }
            } else {
                emptyState(icon: "rectangle.on.rectangle.angled", text: L("No cards"))
            }
        }
    }

    private var speakButton: some View {
        Button {
            vm.speakCurrentWord()
        } label: {
            Image(systemName: vm.speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(vm.speech.isSpeaking ? Color.black.opacity(0.85) : .white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(vm.speech.isSpeaking ? tint : Color.white.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .help(L("Pronounce"))
    }

    @ViewBuilder
    private func phoneticRow(for card: TOEICVocabCard) -> some View {
        // IPA from bundled toeic_vocabulary / toeic_phonetics (offline).
        let ipa = vm.displayPhonetic
        HStack(spacing: 8) {
            if !ipa.isEmpty {
                Text(ipa)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.95))
            } else {
                Text("···")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .frame(minHeight: 20)
    }

    private func roundAction(
        systemName: String,
        help: String,
        tinted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tinted ? Color.black.opacity(0.85) : .white.opacity(0.75))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(tinted ? tint : Color.white.opacity(0.07))
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(tinted ? 0 : 0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Quiz

    private var quizPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = vm.currentQuiz {
                quizQuestionBlock(item: item)

                VStack(spacing: 8) {
                    ForEach(Array(item.choices.enumerated()), id: \.offset) { index, choice in
                        quizChoiceButton(index: index, choice: choice, item: item)
                    }
                }

                if vm.didRevealAnswer {
                    let explanation = (vm.liveExplanation ?? item.explanationVI)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !explanation.isEmpty {
                        Text(explanation)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            }
                            .transition(.opacity)
                    }

                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Button(action: {
                            isQuestionHovered = false
                            vm.nextQuiz()
                        }) {
                            HStack(spacing: 8) {
                                Text(L("Next"))
                                    .font(.system(size: 13, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Color.black.opacity(0.88))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Capsule(style: .continuous).fill(tint))
                        }
                        .buttonStyle(.plain)
                        .help(L("Next question"))
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            } else {
                emptyState(icon: "list.bullet.rectangle", text: L("No questions"))
            }
        }
        .animation(.snappy(duration: 0.22), value: vm.didRevealAnswer)
        .onChange(of: vm.quizIndex) { _, _ in
            isQuestionHovered = false
        }
    }

    /// English stem by default; hover (after answer) swaps to Vietnamese translation.
    private func quizQuestionBlock(item: TOEICQuizItem) -> some View {
        let translation = (vm.liveTranslation ?? TOEICQuizText.lineUnderQuestion(for: item))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canShowTranslation = vm.didRevealAnswer && !translation.isEmpty
        let showingTranslation = canShowTranslation && isQuestionHovered

        return Text(showingTranslation ? translation : item.prompt)
            .font(.system(size: showingTranslation ? 14 : 16, weight: .semibold))
            .foregroundStyle(.white.opacity(showingTranslation ? 0.78 : 0.96))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard canShowTranslation else {
                    isQuestionHovered = false
                    return
                }
                withAnimation(.snappy(duration: 0.18)) {
                    isQuestionHovered = hovering
                }
            }
            .help(canShowTranslation ? L("Hover for translation") : "")
            .animation(.snappy(duration: 0.18), value: showingTranslation)
            .animation(.snappy(duration: 0.18), value: vm.liveTranslation)
    }

    private func quizChoiceButton(index: Int, choice: String, item: TOEICQuizItem) -> some View {
        let revealed = vm.didRevealAnswer
        let selected = vm.selectedChoice == index
        let isCorrect = index == item.correctIndex
        let isFocus = !revealed || isCorrect || selected

        let fill: Color = {
            guard revealed else {
                return selected ? tint.opacity(0.16) : Color.white.opacity(0.05)
            }
            if isCorrect { return Color.green.opacity(0.22) }
            if selected { return Color.red.opacity(0.2) }
            return Color.white.opacity(0.04)
        }()

        let stroke: Color = {
            guard revealed else {
                return selected ? tint.opacity(0.55) : Color.white.opacity(0.1)
            }
            if isCorrect { return Color.green.opacity(0.7) }
            if selected { return Color.red.opacity(0.65) }
            return Color.white.opacity(0.08)
        }()

        let letterColor: Color = {
            if revealed && isCorrect { return Color.green.opacity(0.95) }
            if revealed && selected { return Color.red.opacity(0.9) }
            return Color.white.opacity(isFocus ? 0.55 : 0.4)
        }()

        let textColor: Color = {
            if revealed && isCorrect { return Color.white.opacity(0.98) }
            if revealed && selected { return Color.white.opacity(0.95) }
            return Color.white.opacity(isFocus ? 0.94 : 0.55)
        }()

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                vm.selectChoice(index)
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(UnicodeScalar(65 + index)!))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(letterColor)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(
                            revealed && isCorrect
                                ? Color.green.opacity(0.22)
                                : (revealed && selected ? Color.red.opacity(0.2) : Color.white.opacity(0.06))
                        )
                    )
                Text(choice)
                    .font(.system(size: 14, weight: isCorrect && revealed ? .bold : .semibold))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                if revealed && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.95))
                } else if revealed && selected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!revealed)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stroke, lineWidth: revealed && (isCorrect || selected) ? 1.5 : 1)
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

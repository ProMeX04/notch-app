import Foundation

/// Word bank for draws. Uses bundled Study4 vocabulary (~3.8k); falls back to seed.
/// AI must **draw from this bank** only — never invent free-form headwords.
enum TOEICCatalog {
    /// Primary bank: bundled `Resources/TOEIC/toeic_vocabulary.json`.
    static var wordBank: [TOEICVocabCard] {
        let bundled = TOEICVocabularyBank.allCards
        return bundled.isEmpty ? seedVocab : bundled
    }

    static var vocab: [TOEICVocabCard] { wordBank }

    static let seedVocab: [TOEICVocabCard] = [
        .init(id: "v01", word: "allocate", phonetic: "/ˈæləkeɪt/", meaningVI: "phân bổ, cấp phát", meaningEN: "to distribute resources for a purpose", example: "The manager will allocate funds to marketing.", part: "Business"),
        .init(id: "v02", word: "deadline", phonetic: "/ˈdedlaɪn/", meaningVI: "hạn chót", meaningEN: "the latest time something must be finished", example: "Please submit the report before the deadline.", part: "Business"),
        .init(id: "v03", word: "negotiate", phonetic: "/nɪˈɡoʊʃieɪt/", meaningVI: "đàm phán", meaningEN: "to discuss to reach an agreement", example: "They negotiated a better price with the supplier.", part: "Business"),
        .init(id: "v04", word: "invoice", phonetic: "/ˈɪnvɔɪs/", meaningVI: "hóa đơn", meaningEN: "a bill for goods or services", example: "We received an invoice for the shipment.", part: "Business"),
        .init(id: "v05", word: "revenue", phonetic: "/ˈrevənjuː/", meaningVI: "doanh thu", meaningEN: "income from business activities", example: "Revenue increased by 12% this quarter.", part: "Business"),
        .init(id: "v06", word: "efficient", phonetic: "/ɪˈfɪʃnt/", meaningVI: "hiệu quả (dùng ít tài nguyên)", meaningEN: "working well without waste", example: "The new system is more efficient.", part: "General"),
        .init(id: "v07", word: "reliable", phonetic: "/rɪˈlaɪəbl/", meaningVI: "đáng tin cậy", meaningEN: "can be trusted or depended on", example: "She is a reliable team member.", part: "General"),
        .init(id: "v08", word: "postpone", phonetic: "/poʊˈspoʊn/", meaningVI: "hoãn lại", meaningEN: "to delay until later", example: "The meeting was postponed until Friday.", part: "Business"),
        .init(id: "v09", word: "confirm", phonetic: "/kənˈfɜːrm/", meaningVI: "xác nhận", meaningEN: "to state that something is true", example: "Please confirm your attendance by email.", part: "Business"),
        .init(id: "v10", word: "agenda", phonetic: "/əˈdʒendə/", meaningVI: "chương trình nghị sự", meaningEN: "a list of items to discuss", example: "The agenda includes budget review.", part: "Business"),
        .init(id: "v11", word: "personnel", phonetic: "/ˌpɜːrsəˈnel/", meaningVI: "nhân sự", meaningEN: "employees of an organization", example: "Personnel must wear ID badges.", part: "HR"),
        .init(id: "v12", word: "applicant", phonetic: "/ˈæplɪkənt/", meaningVI: "ứng viên", meaningEN: "a person who applies for a job", example: "There were 50 applicants for the role.", part: "HR"),
        .init(id: "v13", word: "merchandise", phonetic: "/ˈmɜːrtʃəndaɪs/", meaningVI: "hàng hóa", meaningEN: "goods for sale", example: "The store displays new merchandise.", part: "Sales"),
        .init(id: "v14", word: "warranty", phonetic: "/ˈwɔːrənti/", meaningVI: "bảo hành", meaningEN: "a written guarantee", example: "The laptop has a two-year warranty.", part: "Sales"),
        .init(id: "v15", word: "shipment", phonetic: "/ˈʃɪpmənt/", meaningVI: "lô hàng", meaningEN: "goods sent by transport", example: "The shipment arrives on Monday.", part: "Logistics"),
        .init(id: "v16", word: "itinerary", phonetic: "/aɪˈtɪnəreri/", meaningVI: "lịch trình chuyến đi", meaningEN: "a travel plan with times and places", example: "Please email the itinerary to the client.", part: "Travel"),
        .init(id: "v17", word: "accommodate", phonetic: "/əˈkɑːmədeɪt/", meaningVI: "cung cấp chỗ ở; đáp ứng", meaningEN: "to provide lodging or make room for", example: "The hotel can accommodate 200 guests.", part: "Travel"),
        .init(id: "v18", word: "comprehensive", phonetic: "/ˌkɑːmprɪˈhensɪv/", meaningVI: "toàn diện", meaningEN: "including nearly everything", example: "They offered a comprehensive training program.", part: "General"),
        .init(id: "v19", word: "prioritize", phonetic: "/praɪˈɔːrətaɪz/", meaningVI: "ưu tiên", meaningEN: "to treat as more important", example: "We should prioritize customer requests.", part: "Business"),
        .init(id: "v20", word: "collaborate", phonetic: "/kəˈlæbəreɪt/", meaningVI: "hợp tác", meaningEN: "to work together", example: "Teams collaborate on the product launch.", part: "Business"),
        .init(id: "v21", word: "inquire", phonetic: "/ɪnˈkwaɪər/", meaningVI: "hỏi thông tin", meaningEN: "to ask for information", example: "Customers often inquire about delivery times.", part: "Customer"),
        .init(id: "v22", word: "refund", phonetic: "/ˈriːfʌnd/", meaningVI: "hoàn tiền", meaningEN: "money returned to a customer", example: "You may request a full refund within 30 days.", part: "Customer"),
        .init(id: "v23", word: "policy", phonetic: "/ˈpɑːləsi/", meaningVI: "chính sách", meaningEN: "an official rule or plan", example: "Our return policy is printed on the receipt.", part: "Customer"),
        .init(id: "v24", word: "maintenance", phonetic: "/ˈmeɪntənəns/", meaningVI: "bảo trì", meaningEN: "the process of keeping something working", example: "The elevator is under maintenance.", part: "Office"),
        .init(id: "v25", word: "occupancy", phonetic: "/ˈɑːkjəpənsi/", meaningVI: "tỷ lệ lấp đầy / chiếm dụng", meaningEN: "the state of being occupied", example: "Hotel occupancy is high in summer.", part: "Travel"),
        .init(id: "v26", word: "authorize", phonetic: "/ˈɔːθəraɪz/", meaningVI: "ủy quyền, cho phép", meaningEN: "to give official permission", example: "Only managers can authorize discounts.", part: "Business"),
        .init(id: "v27", word: "eligible", phonetic: "/ˈelɪdʒəbl/", meaningVI: "đủ điều kiện", meaningEN: "qualified to do or receive something", example: "Employees are eligible for health benefits.", part: "HR"),
        .init(id: "v28", word: "mandatory", phonetic: "/ˈmændətɔːri/", meaningVI: "bắt buộc", meaningEN: "required by rules", example: "Safety training is mandatory for all staff.", part: "HR"),
        .init(id: "v29", word: "approximately", phonetic: "/əˈprɑːksɪmətli/", meaningVI: "xấp xỉ", meaningEN: "close to a particular number", example: "The trip takes approximately two hours.", part: "General"),
        .init(id: "v30", word: "substantial", phonetic: "/səbˈstænʃl/", meaningVI: "đáng kể", meaningEN: "large in amount or importance", example: "There was a substantial improvement in sales.", part: "Business"),
        .init(id: "v31", word: "facilitate", phonetic: "/fəˈsɪlɪteɪt/", meaningVI: "tạo điều kiện, hỗ trợ", meaningEN: "to make a process easier", example: "Software can facilitate remote collaboration.", part: "Business"),
        .init(id: "v32", word: "outstanding", phonetic: "/aʊtˈstændɪŋ/", meaningVI: "xuất sắc; chưa thanh toán", meaningEN: "excellent; or not yet paid", example: "Please settle all outstanding invoices.", part: "Business"),
        .init(id: "v33", word: "inventory", phonetic: "/ˈɪnvəntɔːri/", meaningVI: "hàng tồn kho", meaningEN: "goods held in stock", example: "We need to check the inventory levels.", part: "Logistics"),
        .init(id: "v34", word: "brochure", phonetic: "/broʊˈʃʊr/", meaningVI: "tờ rơi, brochure", meaningEN: "a booklet with information", example: "Pick up a brochure at the reception desk.", part: "Marketing"),
        .init(id: "v35", word: "subscription", phonetic: "/səbˈskrɪpʃn/", meaningVI: "đăng ký (dịch vụ)", meaningEN: "an arrangement to receive regularly", example: "Your magazine subscription expires next month.", part: "Sales"),
        .init(id: "v36", word: "extension", phonetic: "/ɪkˈstenʃn/", meaningVI: "số máy nhánh; gia hạn", meaningEN: "a phone line number; or extra time", example: "Call extension 204 for support.", part: "Office"),
        .init(id: "v37", word: "venue", phonetic: "/ˈvenjuː/", meaningVI: "địa điểm tổ chức", meaningEN: "the place where an event happens", example: "The conference venue is near the station.", part: "Events"),
        .init(id: "v38", word: "reminder", phonetic: "/rɪˈmaɪndər/", meaningVI: "lời nhắc", meaningEN: "something that makes you remember", example: "This is a reminder about tomorrow’s meeting.", part: "Office"),
        .init(id: "v39", word: "compatible", phonetic: "/kəmˈpætəbl/", meaningVI: "tương thích", meaningEN: "able to work together", example: "The software is compatible with macOS.", part: "Tech"),
        .init(id: "v40", word: "supervise", phonetic: "/ˈsuːpərvaɪz/", meaningVI: "giám sát", meaningEN: "to watch and direct work", example: "She will supervise the new interns.", part: "HR"),
    ]

    static let quiz: [TOEICQuizItem] = [
        .init(
            id: "q01",
            prompt: "The team will _____ the budget for next quarter tomorrow.",
            choices: ["discuss", "discussion", "discussing", "discussed"],
            correctIndex: 0,
            explanationVI: "Sau will + động từ nguyên mẫu: discuss.",
            part: "Part 5"
        ),
        .init(
            id: "q02",
            prompt: "Please send the package to the address _____ on the form.",
            choices: ["indicate", "indicates", "indicated", "indicating"],
            correctIndex: 2,
            explanationVI: "Cần phân từ quá khứ làm tính từ: indicated (được ghi).",
            part: "Part 5"
        ),
        .init(
            id: "q03",
            prompt: "Ms. Chen is responsible _____ training new employees.",
            choices: ["to", "for", "of", "with"],
            correctIndex: 1,
            explanationVI: "responsible for + V-ing/N.",
            part: "Part 5"
        ),
        .init(
            id: "q04",
            prompt: "The seminar was postponed _____ the heavy rain.",
            choices: ["because", "because of", "although", "despite of"],
            correctIndex: 1,
            explanationVI: "because of + N; because + mệnh đề.",
            part: "Part 5"
        ),
        .init(
            id: "q05",
            prompt: "All staff must complete the course _____ Friday.",
            choices: ["until", "by", "during", "since"],
            correctIndex: 1,
            explanationVI: "by = không muộn hơn thời điểm đó (deadline).",
            part: "Part 5"
        ),
        .init(
            id: "q06",
            prompt: "The company offers a _____ range of services.",
            choices: ["wide", "widely", "widen", "width"],
            correctIndex: 0,
            explanationVI: "Cần tính từ bổ nghĩa cho range: wide.",
            part: "Part 5"
        ),
        .init(
            id: "q07",
            prompt: "If you have any questions, _____ free to contact us.",
            choices: ["feel", "feels", "feeling", "felt"],
            correctIndex: 0,
            explanationVI: "Câu mệnh lệnh/lời khuyên: feel free to…",
            part: "Part 5"
        ),
        .init(
            id: "q08",
            prompt: "The report must be submitted _____ the end of the week.",
            choices: ["in", "on", "at", "by"],
            correctIndex: 3,
            explanationVI: "by the end of… = trước khi kết thúc.",
            part: "Part 5"
        ),
        .init(
            id: "q09",
            prompt: "Customers were _____ with the improved service.",
            choices: ["satisfy", "satisfaction", "satisfied", "satisfying"],
            correctIndex: 2,
            explanationVI: "be satisfied with…",
            part: "Part 5"
        ),
        .init(
            id: "q10",
            prompt: "We look forward to _____ from you soon.",
            choices: ["hear", "hearing", "heard", "hears"],
            correctIndex: 1,
            explanationVI: "look forward to + V-ing.",
            part: "Part 5"
        ),
        .init(
            id: "q11",
            prompt: "The manager asked that the files _____ by noon.",
            choices: ["are sent", "be sent", "sending", "to send"],
            correctIndex: 1,
            explanationVI: "Cấu trúc giả định: ask that + S + bare infinitive (be sent).",
            part: "Part 5"
        ),
        .init(
            id: "q12",
            prompt: "Neither the director nor the assistants _____ available today.",
            choices: ["is", "are", "be", "been"],
            correctIndex: 1,
            explanationVI: "neither…nor: động từ theo chủ ngữ gần nhất (assistants → are).",
            part: "Part 5"
        ),
        .init(
            id: "q13",
            prompt: "The product will be available _____ next month.",
            choices: ["on", "in", "at", "for"],
            correctIndex: 1,
            explanationVI: "in + month.",
            part: "Part 5"
        ),
        .init(
            id: "q14",
            prompt: "She works more _____ than any other employee.",
            choices: ["efficient", "efficiently", "efficiency", "efficiencies"],
            correctIndex: 1,
            explanationVI: "Trạng từ bổ nghĩa cho works: efficiently.",
            part: "Part 5"
        ),
        .init(
            id: "q15",
            prompt: "Please keep me _____ of any changes to the schedule.",
            choices: ["inform", "informed", "informing", "information"],
            correctIndex: 1,
            explanationVI: "keep someone informed of…",
            part: "Part 5"
        ),
        .init(
            id: "q16",
            prompt: "The factory operates _____ full capacity during peak season.",
            choices: ["in", "at", "on", "by"],
            correctIndex: 1,
            explanationVI: "at full capacity.",
            part: "Part 5"
        ),
        .init(
            id: "q17",
            prompt: "There has been a significant _____ in customer satisfaction.",
            choices: ["improve", "improved", "improvement", "improving"],
            correctIndex: 2,
            explanationVI: "Sau a significant cần danh từ: improvement.",
            part: "Part 5"
        ),
        .init(
            id: "q18",
            prompt: "Applicants should submit their resumes _____ May 15.",
            choices: ["no later than", "no longer", "no more as", "not late as"],
            correctIndex: 0,
            explanationVI: "no later than = không muộn hơn.",
            part: "Part 5"
        ),
        .init(
            id: "q19",
            prompt: "The instructions were _____ clear for all participants.",
            choices: ["enough", "too", "so", "such"],
            correctIndex: 0,
            explanationVI: "adj + enough (clear enough). “too clear” mang nghĩa tiêu cực khác.",
            part: "Part 5"
        ),
        .init(
            id: "q20",
            prompt: "He has been working here _____ 2019.",
            choices: ["for", "since", "during", "while"],
            correctIndex: 1,
            explanationVI: "since + mốc thời gian; for + khoảng thời gian.",
            part: "Part 5"
        ),
    ]

    // MARK: - Bank draws

    /// Draw `count` cards from the word bank. Prefers cards not in `knownIDs`.
    static func drawVocab(
        count: Int,
        knownIDs: Set<String> = [],
        excludingIDs: Set<String> = []
    ) -> [TOEICVocabCard] {
        let bank = wordBank
        let n = max(0, min(count, bank.count))
        guard n > 0 else { return [] }

        var pool = bank.filter { !excludingIDs.contains($0.id) }
        if pool.count < n {
            pool = bank
        }

        let notKnown = pool.filter { !knownIDs.contains($0.id) }.shuffled()
        let known = pool.filter { knownIDs.contains($0.id) }.shuffled()
        let ordered = notKnown + known
        return Array(ordered.prefix(n))
    }

    /// Pick distractor words from the bank (different from the target).
    static func distractors(for target: TOEICVocabCard, count: Int = 3) -> [String] {
        wordBank
            .filter { $0.id != target.id && $0.word.caseInsensitiveCompare(target.word) != .orderedSame }
            .shuffled()
            .prefix(count)
            .map(\.word)
    }

    /// Offline quiz matching Block Shorts `getFallbackQuestion`:
    /// "Nghĩa của từ X là gì?" + 4 Vietnamese meaning choices.
    static func offlineQuizItem(from card: TOEICVocabCard) -> TOEICQuizItem {
        let correctMeaning = card.meaningVI.trimmingCharacters(in: .whitespacesAndNewlines)
        if correctMeaning.isEmpty {
            // No VI meaning — fall back to English-word choices with cloze/meaning prompt.
            return offlineWordChoiceItem(from: card)
        }

        var seen = Set<String>([correctMeaning.lowercased()])
        var wrong: [String] = []
        for other in wordBank.shuffled() {
            if wrong.count >= 3 { break }
            let m = other.meaningVI.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !m.isEmpty, !seen.contains(m.lowercased()) else { continue }
            seen.insert(m.lowercased())
            wrong.append(m)
        }
        let placeholders = ["(khác)", "(khác biệt)", "(không phải)"]
        for p in placeholders where wrong.count < 3 {
            if !seen.contains(p.lowercased()) {
                seen.insert(p.lowercased())
                wrong.append(p)
            }
        }

        var choices = [correctMeaning] + Array(wrong.prefix(3))
        choices.shuffle()
        let correctIndex = choices.firstIndex(of: correctMeaning) ?? 0
        let phonetic = card.phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String = {
            if phonetic.isEmpty {
                return "Nghĩa của từ \"\(card.word)\" là gì?"
            }
            return "Nghĩa của từ \"\(card.word)\" (\(phonetic)) là gì?"
        }()
        return TOEICQuizItem(
            id: "bank-q-\(card.id)",
            prompt: prompt,
            choices: Array(choices.prefix(4)),
            correctIndex: min(correctIndex, 3),
            explanationVI: "Từ \"\(card.word)\" có nghĩa là: \(correctMeaning).",
            part: card.part
        )
    }

    /// English-word multiple choice (used when meaning is missing).
    private static func offlineWordChoiceItem(from card: TOEICVocabCard) -> TOEICQuizItem {
        let distractorWords = distractors(for: card, count: 3)
        var choices = distractorWords + [card.word]
        choices.shuffle()
        let correctIndex = choices.firstIndex(of: card.word) ?? 0
        return TOEICQuizItem(
            id: "bank-q-\(card.id)",
            prompt: quizPrompt(for: card),
            choices: choices,
            correctIndex: correctIndex,
            explanationVI: "\(card.word): \(card.meaningVI)".trimmingCharacters(in: .whitespaces),
            part: card.part
        )
    }

    /// Prefer real cloze from example; otherwise meaning-based (Study4 has empty examples).
    static func quizPrompt(for card: TOEICVocabCard) -> String {
        let ex = card.example.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHighQualityClozePrompt(ex, targetWord: card.word),
           let range = ex.range(of: card.word, options: .caseInsensitive) {
            return normalizeBlank(ex.replacingCharacters(in: range, with: "_____"))
        }
        return meaningQuizPrompt(for: card)
    }

    /// English-word from VI meaning (legacy reverse style).
    static func meaningQuizPrompt(for card: TOEICVocabCard) -> String {
        let meaning = card.meaningVI.trimmingCharacters(in: .whitespacesAndNewlines)
        if !meaning.isEmpty {
            let pos = card.part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pos.isEmpty, pos.caseInsensitiveCompare("Word") != .orderedSame {
                return "Chọn từ tiếng Anh có nghĩa “\(meaning)” (\(pos))."
            }
            return "Chọn từ tiếng Anh có nghĩa “\(meaning)”."
        }
        let en = card.meaningEN.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty, en.caseInsensitiveCompare("Word") != .orderedSame {
            return "Which English word means “\(en)”?"
        }
        return "Chọn từ tiếng Anh đúng cho: \(card.word.prefix(1))…"
    }

    /// Temporary offline quiz while AI generates: meaning questions from vocab only.
    static func offlineQuizDeck(vocabCards: [TOEICVocabCard], limit: Int = 40) -> [TOEICQuizItem] {
        var items = vocabCards.prefix(max(limit, 0)).map { offlineQuizItem(from: $0) }
        if items.isEmpty {
            items = seedVocab.prefix(limit).map { offlineQuizItem(from: $0) }
        }
        if items.isEmpty {
            items = quiz
        }
        return Array(items.prefix(limit))
    }

    /// Accept only concrete business cloze sentences; reject AI meta-prompts.
    static func isHighQualityClozePrompt(_ prompt: String, targetWord: String) -> Bool {
        let normalized = normalizeWhitespace(prompt)
        guard normalized.count >= 24 else { return false }

        let lower = normalized.lowercased()
        let bannedSubstrings = [
            "best word for this context",
            "best word for the context",
            "best word in this context",
            "best word for this",
            "for this context is",
            "choose the best word",
            "select the best word",
            "select the correct word",
            "which word best",
            "which is the best word",
            "fill in the blank",
            "fill in the blanks",
            "complete the sentence with",
            "the correct word is",
            "pick the right word",
            "most appropriate word",
        ]
        if bannedSubstrings.contains(where: { lower.contains($0) }) {
            return false
        }

        let word = targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBlank = normalized.contains("_____")
            || normalized.contains("___")
            || normalized.contains("…")
            || normalized.contains("...")
        let containsTarget = !word.isEmpty
            && normalized.range(of: word, options: .caseInsensitive) != nil

        // Finished cloze: needs a blank and must not leak the answer.
        // Raw example (for blanking): no blank yet, but must contain the target word.
        if hasBlank {
            if containsTarget { return false }
        } else if !containsTarget {
            return false
        }

        let withoutBlank = normalized
            .replacingOccurrences(of: "_____", with: " ")
            .replacingOccurrences(of: "___", with: " ")
            .replacingOccurrences(of: "…", with: " ")
            .replacingOccurrences(of: "...", with: " ")
        let tokens = withoutBlank
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { $0.count > 1 }
        // Need enough real sentence context around the blank.
        guard tokens.count >= 5 else { return false }
        return true
    }

    /// If AI/offline stem is junk, replace with meaning prompt.
    static func sanitizedQuizPrompt(_ prompt: String, for card: TOEICVocabCard) -> String {
        let p = normalizeWhitespace(prompt)
        if isHighQualityClozePrompt(p, targetWord: card.word) {
            return normalizeBlank(p)
        }
        return meaningQuizPrompt(for: card)
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeBlank(_ text: String) -> String {
        var s = normalizeWhitespace(text)
        s = s.replacingOccurrences(of: "_{3,}", with: "_____", options: .regularExpression)
        s = s.replacingOccurrences(of: "…", with: "_____")
        s = s.replacingOccurrences(of: "...", with: "_____")
        return s
    }
}

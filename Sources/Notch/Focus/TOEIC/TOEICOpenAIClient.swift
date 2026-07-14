import Foundation

/// Minimal OpenAI-compatible chat client for local gateway (default `http://localhost:20128/v1`).
struct TOEICOpenAIClient: Sendable {
    var baseURL: URL
    var apiKey: String
    var model: String
    var session: URLSession

    static let defaultBaseURLString = "http://localhost:20128/v1"
    static let defaultModel = "gemini/gemini-3.1-flash-lite-preview"
    static let baseURLDefaultsKey = "notch.toeic.openai.baseURL"
    static let modelDefaultsKey = "notch.toeic.openai.model"
    static let apiKeyDefaultsKey = "notch.toeic.openai.apiKey"

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TOEICOpenAIClient {
        let base = defaults.string(forKey: baseURLDefaultsKey) ?? defaultBaseURLString
        let model = defaults.string(forKey: modelDefaultsKey) ?? defaultModel
        let key = defaults.string(forKey: apiKeyDefaultsKey) ?? "local"
        return TOEICOpenAIClient(
            baseURL: URL(string: base) ?? URL(string: defaultBaseURLString)!,
            apiKey: key,
            model: model,
            session: .shared
        )
    }

    enum ClientError: LocalizedError {
        case invalidURL
        case httpStatus(Int, String)
        case emptyContent
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .httpStatus(let code, let body): return "API \(code): \(body.prefix(200))"
            case .emptyContent: return "Empty model response"
            case .decodeFailed: return "Could not parse model JSON"
            }
        }
    }

    /// Structured output modes (OpenAI-compatible `response_format`).
    /// Gateway probe: `json_object` is honored; full `json_schema` may be ignored by some Gemini routes.
    /// Not `Sendable` because JSON Schema dictionaries use `[String: Any]`.
    enum ResponseFormat {
        case text
        /// Forces a JSON object body (`response_format: { type: "json_object" }`).
        case jsonObject
        /// OpenAI strict JSON Schema (best effort; falls through if gateway ignores it).
        case jsonSchema(name: String, schema: [String: Any], strict: Bool)

        fileprivate var bodyValue: [String: Any]? {
            switch self {
            case .text:
                return nil
            case .jsonObject:
                return ["type": "json_object"]
            case .jsonSchema(let name, let schema, let strict):
                return [
                    "type": "json_schema",
                    "json_schema": [
                        "name": name,
                        "strict": strict,
                        "schema": schema,
                    ] as [String: Any],
                ]
            }
        }
    }

    /// JSON Schema for one Block Shorts–style TOEIC quiz exercise.
    /// Built as functions (not static `let [String: Any]`) for Swift 6 concurrency safety.
    static func toeicQuizJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "mode": ["type": "string"],
                "question": [
                    "type": "string",
                    "description": "TOEIC Part 5 sentence with a single _____ blank",
                ],
                "answer": [
                    "type": "string",
                    "description": "Correct option text, must match one entry in options exactly",
                ],
                "options": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 4,
                    "maxItems": 4,
                ],
                "explanation": [
                    "type": "string",
                    "description": "Vietnamese grammar/vocab explanation",
                ],
                "translation": [
                    "type": "string",
                    "description": "Full Vietnamese translation of the completed sentence",
                ],
            ],
            "required": ["mode", "question", "answer", "options", "explanation", "translation"],
            "additionalProperties": false,
        ]
    }

    static func examplesJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "example": ["type": "string"],
                        ],
                        "required": ["id", "example"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["items"],
            "additionalProperties": false,
        ]
    }

    static func phoneticJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "ipa": ["type": "string", "description": "IPA transcription, may include slashes"],
            ],
            "required": ["ipa"],
            "additionalProperties": false,
        ]
    }

    static func explainJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "explanation": ["type": "string", "description": "Vietnamese explanation 2-4 sentences"],
            ],
            "required": ["explanation"],
            "additionalProperties": false,
        ]
    }

    func chat(
        system: String,
        user: String,
        temperature: Double = 0.4,
        maxTokens: Int = 1200,
        responseFormat: ResponseFormat = .text
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let rf = responseFormat.bodyValue {
            body["response_format"] = rf
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(status, text)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw ClientError.decodeFailed
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.emptyContent }
        return trimmed
    }

    /// Prefer JSON Schema structured output; if the gateway returns non-JSON prose
    /// (some Gemini routes ignore `json_schema`), retry with `json_object`.
    func chatStructured(
        system: String,
        user: String,
        temperature: Double = 0.4,
        maxTokens: Int = 1200,
        schemaName: String,
        schema: [String: Any],
        strict: Bool = true
    ) async throws -> String {
        let schemaFormat = ResponseFormat.jsonSchema(name: schemaName, schema: schema, strict: strict)
        do {
            let raw = try await chat(
                system: system,
                user: user,
                temperature: temperature,
                maxTokens: maxTokens,
                responseFormat: schemaFormat
            )
            if looksLikeJSONObject(raw) { return raw }
        } catch {
            // Fall through to json_object.
        }

        return try await chat(
            system: system,
            user: user,
            temperature: temperature,
            maxTokens: maxTokens,
            responseFormat: .jsonObject
        )
    }

    private func looksLikeJSONObject(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("{") { return true }
        // fenced
        if s.hasPrefix("```"), s.contains("{") { return true }
        return false
    }
}

/// AI quiz generation aligned with Block Shorts `handleGenerateVocabExercise` (mode "quiz"),
/// using OpenAI-compatible **structured outputs** (`response_format`).
enum TOEICAIGenerator {
    /// Generate `count` TOEIC Part 5/6 exercises:
    /// seed with bank words → structured JSON quiz → TOEICQuizItem.
    /// Falls back to offline (permanent Part 5 + meaning quiz) per failed item.
    static func generateQuizFromBank(
        targets: [TOEICVocabCard],
        distractorPool: [TOEICVocabCard],
        client: TOEICOpenAIClient = .fromDefaults()
    ) async throws -> [TOEICQuizItem] {
        guard !targets.isEmpty else { return [] }

        var items: [TOEICQuizItem] = []
        var exclude: [String] = []
        let seedPool = (targets + distractorPool.shuffled().prefix(20)).uniqued(by: \.id)

        for (idx, focus) in targets.enumerated() {
            var seeds = [focus]
            let extras = seedPool
                .filter { $0.id != focus.id }
                .shuffled()
                .prefix(4)
            seeds.append(contentsOf: extras)

            if let item = try? await generateOneExtensionStyleQuiz(
                seeds: seeds,
                excludeSentences: exclude,
                focus: focus,
                client: client
            ) {
                items.append(item)
                exclude.append(item.prompt)
                if exclude.count > 20 { exclude = Array(exclude.suffix(20)) }
            } else {
                items.append(TOEICCatalog.offlineQuizItem(from: focus))
            }

            if idx + 1 < targets.count {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return items
    }

    /// One exercise — Block Shorts quiz schema via structured output.
    static func generateOneExtensionStyleQuiz(
        seeds: [TOEICVocabCard],
        excludeSentences: [String],
        focus: TOEICVocabCard?,
        client: TOEICOpenAIClient = .fromDefaults()
    ) async throws -> TOEICQuizItem {
        let seedPayload: [[String: String]] = seeds.map { card in
            [
                "word": card.word,
                "meaning": card.meaningVI,
                "pos": card.part,
                "pronunciation": card.phonetic,
            ]
        }

        var excludeBlock = ""
        if !excludeSentences.isEmpty {
            let encodedData = try? JSONSerialization.data(withJSONObject: Array(excludeSentences.prefix(12)))
            let encoded = encodedData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            excludeBlock = """
            Avoid these already-shown questions: \(encoded)
            """
        }

        let seedData = try? JSONSerialization.data(withJSONObject: seedPayload, options: [.sortedKeys])
        let seedJSON = seedData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let system = """
        You are a professional TOEIC test generator (Part 5 & 6).
        Output MUST match the structured JSON schema (mode quiz).
        Fields: mode, question, answer, options[4], explanation (VI), translation (VI).
        """

        let user = """
        Create 1 English TOEIC quiz exercise.
        Seed vocabulary (prefer focusing on the first word):
        \(seedJSON)
        \(excludeBlock)

        Content rules:
        - Vary focus: Vocabulary (collocations), Grammar (tense/passive/preposition), or Word Forms (N/V/Adj/Adv).
        - question: realistic business English with exactly one _____ blank (never a meta line like "The best word for this context is _____").
        - options: exactly 4 distinct choices; randomize correct position.
        - answer: exact text of the correct option (must equal one of options).
        - explanation: detailed Vietnamese grammar/vocab note.
        - translation: full Vietnamese sentence with the blank filled.
        - mode: "quiz"
        """

        let raw = try await client.chatStructured(
            system: system,
            user: user,
            temperature: 0.5,
            maxTokens: 900,
            schemaName: "toeic_quiz",
            schema: TOEICOpenAIClient.toeicQuizJSONSchema(),
            strict: true
        )
        guard let item = parseExtensionQuizExercise(raw, fallbackFocus: focus) else {
            throw TOEICOpenAIClient.ClientError.decodeFailed
        }
        return item
    }

    /// "AI Vocab" = draw from bank, optionally refresh **example only**.
    static func enhanceExamplesFromBank(
        cards: [TOEICVocabCard],
        client: TOEICOpenAIClient = .fromDefaults()
    ) async throws -> [TOEICVocabCard] {
        guard !cards.isEmpty else { return [] }

        let bankList = cards.map { card in
            "id=\(card.id) | word=\(card.word) | vi=\(card.meaningVI) | en=\(card.meaningEN)"
        }.joined(separator: "\n")

        let system = """
        You write one new business-English example sentence per FIXED bank word.
        Do NOT invent new headwords. Output matches the JSON schema with key "items".
        Each item: { "id": bank id, "example": sentence containing the exact target word }.
        """
        let user = "Write examples for:\n\(bankList)"

        do {
            let raw = try await client.chatStructured(
                system: system,
                user: user,
                temperature: 0.5,
                maxTokens: 1600,
                schemaName: "toeic_examples",
                schema: TOEICOpenAIClient.examplesJSONSchema(),
                strict: true
            )
            let examples = try decodeExamples(from: raw)
            var byID: [String: String] = [:]
            for ex in examples {
                if byID[ex.id] == nil { byID[ex.id] = ex.example }
            }
            return cards.map { card in
                if let ex = byID[card.id], !ex.isEmpty {
                    return TOEICVocabCard(
                        id: card.id,
                        word: card.word,
                        phonetic: card.phonetic,
                        meaningVI: card.meaningVI,
                        meaningEN: card.meaningEN,
                        example: ex,
                        part: card.part
                    )
                }
                return card
            }
        } catch {
            return cards
        }
    }

    /// Translate a completed English TOEIC sentence to Vietnamese (for missing bank translations).
    static func translateSentence(
        _ english: String,
        client: TOEICOpenAIClient = .fromDefaults()
    ) async throws -> String {
        let system = """
        You translate TOEIC business English sentences into natural Vietnamese.
        Output JSON matching schema { "translation": "..." } only.
        Do not add notes or the English source.
        """
        let user = "Translate to Vietnamese:\n\(english)"
        let raw = try await client.chatStructured(
            system: system,
            user: user,
            temperature: 0.2,
            maxTokens: 220,
            schemaName: "toeic_translation",
            schema: [
                "type": "object",
                "properties": [
                    "translation": ["type": "string"],
                ],
                "required": ["translation"],
                "additionalProperties": false,
            ],
            strict: true
        )
        if let data = extractJSONObjectData(from: raw),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["translation"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func explainWrongAnswer(
        prompt: String,
        choices: [String],
        selectedIndex: Int,
        correctIndex: Int,
        client: TOEICOpenAIClient = .fromDefaults()
    ) async throws -> String {
        let system = """
        Explain TOEIC Part 5 answers briefly in Vietnamese (2-4 sentences).
        Output matches JSON schema: { "explanation": "..." }.
        """
        let choiceLines = choices.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
        let user = """
        Question: \(prompt)
        Choices:
        \(choiceLines)
        Student chose: \(selectedIndex)
        Correct: \(correctIndex)
        """
        let raw = try await client.chatStructured(
            system: system,
            user: user,
            temperature: 0.3,
            maxTokens: 400,
            schemaName: "toeic_explain",
            schema: TOEICOpenAIClient.explainJSONSchema(),
            strict: true
        )
        if let data = extractJSONObjectData(from: raw),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["explanation"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If model returned plain text despite schema, use raw after stripping fences.
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
            s = s.replacingOccurrences(of: "```", with: "")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    // MARK: - Parse extension schema

    private struct ExtensionQuizDTO: Decodable {
        let mode: String?
        let question: String
        let answer: String
        let options: FlexibleOptions
        let explanation: String?
        let translation: String?
    }

    /// options may be ["a","b","c","d"] or {"A":"...","B":"..."}.
    private struct FlexibleOptions: Decodable {
        let values: [String]

        init(from decoder: Decoder) throws {
            if let arr = try? decoder.singleValueContainer().decode([String].self) {
                values = arr
                return
            }
            if let dict = try? decoder.singleValueContainer().decode([String: String].self) {
                let order = ["A", "B", "C", "D", "a", "b", "c", "d"]
                var out: [String] = []
                for key in order {
                    if let v = dict[key], !out.contains(v) { out.append(v) }
                }
                for (_, v) in dict.sorted(by: { $0.key < $1.key }) where !out.contains(v) {
                    out.append(v)
                }
                values = out
                return
            }
            values = []
        }
    }

    private static func parseExtensionQuizExercise(
        _ raw: String,
        fallbackFocus: TOEICVocabCard?
    ) -> TOEICQuizItem? {
        guard let data = extractJSONObjectData(from: raw) else { return nil }
        guard let dto = try? JSONDecoder().decode(ExtensionQuizDTO.self, from: data) else {
            return nil
        }

        let question = TOEICCatalog.normalizeWhitespace(dto.question)
        guard !question.isEmpty else { return nil }

        let lower = question.lowercased()
        let banned = [
            "best word for this context",
            "for this context is",
            "choose the best word",
            "fill in the blank",
            "select the best word",
        ]
        if banned.contains(where: { lower.contains($0) }) {
            return nil
        }
        let hasBlank = question.contains("_____") || question.contains("___")
        if !hasBlank && question.count < 28 {
            return nil
        }

        let choices = dto.options.values
            .map { TOEICQuestionBank.stripOptionLabel($0) }
            .filter { !$0.isEmpty }
        guard choices.count >= 2 else { return nil }

        let limited = Array(choices.prefix(4))
        guard let correctIndex = TOEICQuestionBank.answerIndex(
            answer: dto.answer,
            choices: limited,
            rawOptions: dto.options.values
        ) else {
            return nil
        }

        var explanation = (dto.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var translation = (dto.translation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if explanation.isEmpty, let focus = fallbackFocus {
            explanation = "\(focus.word): \(focus.meaningVI)"
        }
        // Init will also split "Dịch câu:" if model stuffed both into explanation.
        if translation.isEmpty {
            let split = TOEICQuizText.splitExplanationAndTranslation(explanation: explanation, translation: "")
            explanation = split.explanation
            translation = split.translation
        }

        let idSuffix = fallbackFocus?.id ?? UUID().uuidString
        return TOEICQuizItem(
            id: "ext-ai-\(idSuffix)-\(abs(question.hashValue))",
            prompt: TOEICCatalog.normalizeBlank(question),
            choices: limited,
            correctIndex: min(correctIndex, limited.count - 1),
            explanationVI: explanation,
            part: "Part 5",
            translationVI: translation
        )
    }

    private static func extractJSONObjectData(from raw: String) -> Data? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
            s = s.replacingOccurrences(of: "```", with: "")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end {
            s = String(s[start...end])
        }
        return Data(s.utf8)
    }

    private struct ExampleRow: Decodable {
        let id: String
        let example: String
    }

    private struct ExamplesWrapper: Decodable {
        let items: [ExampleRow]
    }

    private static func decodeExamples(from raw: String) throws -> [(id: String, example: String)] {
        guard let data = extractJSONObjectData(from: raw) ?? {
            // Bare array fallback
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let start = s.firstIndex(of: "["), let end = s.lastIndex(of: "]"), start < end {
                return Data(String(s[start...end]).utf8)
            }
            return nil
        }() else {
            throw TOEICOpenAIClient.ClientError.decodeFailed
        }

        if let wrapped = try? JSONDecoder().decode(ExamplesWrapper.self, from: data) {
            return wrapped.items.map { ($0.id, $0.example) }
        }
        if let rows = try? JSONDecoder().decode([ExampleRow].self, from: data) {
            return rows.map { ($0.id, $0.example) }
        }
        throw TOEICOpenAIClient.ClientError.decodeFailed
    }
}

private extension Array {
    func uniqued<H: Hashable>(by keyPath: KeyPath<Element, H>) -> [Element] {
        var seen = Set<H>()
        var out: [Element] = []
        for el in self {
            let key = el[keyPath: keyPath]
            if seen.insert(key).inserted {
                out.append(el)
            }
        }
        return out
    }
}

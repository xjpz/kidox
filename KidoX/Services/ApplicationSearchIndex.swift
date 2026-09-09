import Foundation

/// Derived text only. Layout, visibility and usage stay on the original records.
struct ApplicationSearchIndex: Sendable {
    struct Input: Hashable, Sendable {
        let id: UUID
        let customName: String?
        let name: String
        let bundleName: String?
        let bundleIdentifier: String?
        let aliases: [LocalizedApplicationName]
        let legacyAliases: [String]
        let language: String

        init(_ item: LaunchItem, language: String) {
            id = item.id; customName = item.customDisplayName; name = item.displayName
            bundleName = item.bundleName; bundleIdentifier = item.bundleIdentifier
            aliases = item.localizedSearchNames ?? []; legacyAliases = item.localizedDisplayNames ?? []
            self.language = language.lowercased().replacingOccurrences(of: "_", with: "-")
        }
    }

    struct Entry: Sendable {
        struct Term: Hashable, Sendable {
            let text: String
            let source: Int
            let weak: Bool
            let metadata: Bool
        }
        struct Phonetic: Hashable, Sendable {
            let form: PinyinSearchNormalizer.Form
            let source: Int
        }
        let input: Input
        let terms: [Term]
        let phonetics: [Phonetic]
        let isReady: Bool

        init(_ input: Input, includePinyin: Bool = true) {
            self.input = input
            isReady = includePinyin
            var terms: [Term] = [], phonetics: [Phonetic] = []
            var seenTerms = Set<Term>(), seenPhonetics = Set<Phonetic>()
            func add(_ name: String?, source: Int, weak: Bool = false, metadata: Bool = false, chinese: Bool = false) {
                guard let name else { return }
                let normalized = name.kidoXSearchNormalized
                for word in [normalized] + normalized.kidoXSearchTokens where !word.isEmpty {
                    let term = Term(text: word, source: source, weak: weak, metadata: metadata)
                    if seenTerms.insert(term).inserted { terms.append(term) }
                }
                if includePinyin, chinese {
                    for form in PinyinSearchNormalizer.forms(for: name) {
                        let phonetic = Phonetic(form: form, source: source)
                        if seenPhonetics.insert(phonetic).inserted { phonetics.append(phonetic) }
                    }
                }
            }
            let chinese = input.language.hasPrefix("zh")
            add(input.customName, source: 0, chinese: true)
            add(input.name, source: 1, chinese: chinese)
            add(input.bundleName, source: 2, chinese: chinese)
            for alias in input.aliases {
                let locale = alias.localeIdentifier.lowercased().replacingOccurrences(of: "_", with: "-")
                let zh = locale == "zh" || locale.hasPrefix("zh-")
                let english = locale == "en" || locale.hasPrefix("en-")
                let active = locale.split(separator: "-").first == input.language.split(separator: "-").first
                add(alias.name, source: zh ? 3 : (active ? 4 : 5), weak: !(zh || english || active), chinese: zh)
            }
            for alias in input.legacyAliases { add(alias, source: 6, weak: true) }
            add(input.bundleIdentifier, source: 7, weak: true, metadata: true)
            self.terms = terms
            self.phonetics = phonetics
        }

        func match(_ query: LaunchItemSearchQuery) -> LaunchItemSearchMatch? {
            var scores: [Int] = []
            for token in query.tokens {
                guard let best = bestScore(token) else { return nil }
                scores.append(best)
            }
            // Multiword AND: the weakest required match sets the tier; no token can disappear.
            let weakestClass = ((scores.max() ?? 0) / 100) * 100
            return LaunchItemSearchMatch(score: weakestClass + min(scores.reduce(0) { $0 + $1 % 100 }, 99))
        }

        private func bestScore(_ token: String) -> Int? {
            var best: Int?
            func consider(_ tier: Int, _ source: Int, _ penalty: Int = 0) {
                let score = tier * 10_000 + source * 100 + min(max(penalty, 0), 99)
                best = min(best ?? Int.max, score)
            }
            for term in terms {
                let text = term.text
                if term.weak {
                    let minimum = term.metadata ? 3 : 2
                    if token.count >= minimum, text == token { consider(7, term.source); continue }
                    if token.count >= 3, text.hasPrefix(token) { consider(7, term.source, text.count - token.count) }
                    continue
                }
                if text == token { consider(0, term.source); continue }
                if text.hasPrefix(token) { consider(2, term.source, text.count - token.count); continue }
                let initials = text.kidoXSearchInitials
                if initials.hasPrefix(token) { consider(4, term.source, initials.count - token.count) }
                if token.count >= 2, text.first == token.first,
                   let penalty = text.kidoXSubsequenceScore(for: token) { consider(4, term.source, penalty) }
                if let range = text.range(of: token) {
                    consider(5, term.source, text.distance(from: text.startIndex, to: range.lowerBound))
                }
                if token.count >= 3, text.count <= 40,
                   let distance = text.kidoXEditDistance(to: token, limit: token.count >= 6 ? 2 : 1) {
                    consider(6, term.source, distance * 8 + abs(text.count - token.count))
                }
            }
            for phonetic in phonetics {
                let form = phonetic.form
                if token.count >= 2 && (form.full == token || form.initials == token) {
                    consider(1, phonetic.source)
                } else if form.full.hasPrefix(token) || form.initials.hasPrefix(token) {
                    consider(3, phonetic.source, min(form.full.count, form.initials.count) - token.count)
                } else if token.count >= 2,
                          form.suffixes.contains(where: { $0.hasPrefix(token) }) || form.initials.contains(token) {
                    consider(4, phonetic.source)
                }
            }
            return best
        }
    }

    struct Work: Sendable {
        let generation: Int
        let inputs: [Input]
        func build() -> [UUID: Entry] {
            var entries: [UUID: Entry] = [:]
            for input in inputs {
                if Task.isCancelled { break }
                entries[input.id] = Entry(input)
            }
            return entries
        }
    }

    private(set) var entries: [UUID: Entry] = [:]
    private(set) var generation = 0
    private(set) var revision = 0

    /// Installs cheap literal-only fallbacks immediately. Usage/position changes return no work.
    mutating func prepare(items: [LaunchItem], language: String) -> Work? {
        let inputs = Dictionary(items.map { ($0.id, Input($0, language: language)) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for id in Array(entries.keys) where inputs[id] == nil { entries[id] = nil; changed = true }
        for (id, input) in inputs where entries[id]?.input != input {
            entries[id] = Entry(input, includePinyin: false)
            changed = true
        }
        guard changed else { return nil }
        generation += 1
        revision += 1
        return Work(generation: generation, inputs: entries.values.filter { !$0.isReady }.map(\.input))
    }

    @discardableResult
    mutating func apply(_ built: [UUID: Entry], generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        for (id, entry) in built where entries[id]?.input == entry.input { entries[id] = entry }
        revision += 1
        return true
    }

    func match(item: LaunchItem, query: LaunchItemSearchQuery) -> LaunchItemSearchMatch? {
        guard !item.isHidden, item.kind != .folder else { return nil }
        return entries[item.id]?.match(query)
    }
}

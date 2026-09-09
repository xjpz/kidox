import Foundation

enum PinyinSearchNormalizer {
    struct Form: Hashable, Sendable {
        let full: String
        let initials: String
        let suffixes: [String]
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0x20000...0x323AF).contains($0.value)
        }
    }

    static func forms(for name: String, transform: (String) -> String? = {
        $0.applyingTransform(.mandarinToLatin, reverse: false)
    }) -> [Form] {
        guard containsHan(name) else { return [] }
        // Correct demonstrated phrase-level readings, not individual polyphonic characters.
        let corrected = name.replacingOccurrences(of: "音乐", with: " yin yue ")
            .replacingOccurrences(of: "音樂", with: " yin yue ")
        guard let latin = transform(corrected) else { return [] }
        let vLatin = latin.precomposedStringWithCanonicalMapping.map { character in
            "üǖǘǚǜÜǕǗǙǛ".contains(character) ? "v" : String(character)
        }.joined()
        let syllables = vLatin.kidoXSearchNormalized.kidoXSearchTokens
        guard !syllables.isEmpty, !syllables.contains(where: containsHan) else { return [] }
        func form(_ parts: [String]) -> Form {
            Form(full: parts.joined(), initials: parts.compactMap(\.first).map(String.init).joined(),
                 suffixes: parts.indices.dropFirst().map { parts[$0...].joined() })
        }
        let primary = form(syllables)
        let compatible = form(syllables.map { $0.replacingOccurrences(of: "v", with: "u") })
        return primary == compatible ? [primary] : [primary, compatible]
    }
}

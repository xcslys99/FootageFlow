import Foundation

enum KeywordEngine {
    private static let phraseMap: [(String, String)] = [
        ("阿根廷", "Argentina"), ("布宜诺斯艾利斯", "Buenos Aires"), ("银行挤兑", "bank run"),
        ("经济危机", "economic crisis"), ("金融危机", "financial crisis"), ("银行", "bank"),
        ("排队取钱", "bank queue withdrawal"), ("排队", "queue"), ("取钱", "withdrawal"),
        ("恶性通胀", "hyperinflation"), ("金融封锁", "banking restrictions"), ("国家", "country"),
        ("城市", "city"), ("工厂", "factory"), ("街道", "street"), ("历史", "history"),
        ("人物", "people"), ("地图", "map"), ("新闻", "news footage"), ("纪录片", "documentary")
    ]

    static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    static func keywords(for original: String, translated: String? = nil) -> [SearchKeyword] {
        let compact = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return [] }
        var candidates: [String] = []
        if let translated = translated?.cleanQuery, !translated.isEmpty { candidates.append(translated) }

        let regex = try? NSRegularExpression(pattern: "(?:18|19|20)\\d{2}")
        let range = NSRange(compact.startIndex..., in: compact)
        let years = regex?.matches(in: compact, range: range).compactMap { Range($0.range, in: compact).map { String(compact[$0]) } } ?? []
        var mapped: [String] = []
        for (chinese, english) in phraseMap where compact.localizedCaseInsensitiveContains(chinese) { mapped.append(english) }
        let entities = unique(mapped)
        if !entities.isEmpty { candidates.append((years + entities).joined(separator: " ")) }

        if compact.contains("阿根廷") && (compact.contains("挤兑") || compact.contains("经济危机")) {
            if let year = years.first { candidates += ["Argentina financial crisis \(year)", "Argentina bank run \(year)"] }
            candidates += ["Buenos Aires bank queue", "people waiting bank ATM withdrawal"]
        } else {
            let visual = entities.filter { !["history", "country", "documentary"].contains($0) }
            if !visual.isEmpty { candidates.append(visual.prefix(5).joined(separator: " ")) }
        }
        if !containsChinese(compact) { candidates.insert(compact.cleanQuery, at: 0) }
        else { candidates.append(compact) }
        return unique(candidates.map(\.cleanQuery).filter { !$0.isEmpty }).prefix(6).map { SearchKeyword(text: $0) }
    }

    static func mergeTranslation(_ translation: String, into keywords: [SearchKeyword]) -> [SearchKeyword] {
        let translated = translation.cleanQuery
        guard !translated.isEmpty else { return keywords }
        var result = keywords
        if !result.contains(where: { $0.text.caseInsensitiveCompare(translated) == .orderedSame }) {
            result.insert(SearchKeyword(text: translated), at: 0)
        }
        return Array(result.prefix(6))
    }

    static func splitScript(_ script: String) -> [String] {
        let normalized = script.replacingOccurrences(of: "\r\n", with: "\n")
        let separated = normalized.replacingOccurrences(of: "\\n\\s*\\n", with: "\n\u{0000}\n", options: .regularExpression)
        let paragraphs = separated.components(separatedBy: "\u{0000}")
        var output: [String] = []
        for paragraph in paragraphs {
            let clean = paragraph.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let sentences = clean.split(whereSeparator: { "。！？!?；;".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var buffer = ""
            for sentence in sentences {
                if buffer.count + sentence.count <= 80 { buffer += (buffer.isEmpty ? "" : "。") + sentence }
                else { if !buffer.isEmpty { output.append(buffer + "。") }; buffer = sentence }
            }
            if !buffer.isEmpty { output.append(buffer + (buffer.hasSuffix("。") ? "" : "。")) }
        }
        return output
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

private extension String {
    var cleanQuery: String {
        String(prefix(100)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

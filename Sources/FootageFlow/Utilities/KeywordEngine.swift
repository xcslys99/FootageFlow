import Foundation

enum KeywordEngine {
  private struct PhraseRule: Sendable {
    let terms: [String]
    let canonical: String
    let expansions: [String]
  }

  /// Compact, curated, local rules. They intentionally cover high-value creator vocabulary
  /// instead of pretending to be a general machine translation service.
  private static let phraseRules: [PhraseRule] = [
    PhraseRule(
      terms: ["hamburger", "burger", "汉堡", "漢堡", "ハンバーガー", "햄버거", "hamburguesa", "hambúrguer"],
      canonical: "hamburger", expansions: ["burger", "cheeseburger", "hamburger cooking"]),
    PhraseRule(
      terms: [
        "fries", "french fries", "薯条", "薯條", "フライドポテト", "감자튀김", "papas fritas", "batata frita",
      ],
      canonical: "french fries", expansions: ["fries", "potato fries", "french fries cooking"]),
    PhraseRule(
      terms: ["coffee shop", "咖啡店", "咖啡館", "喫茶店", "커피숍", "cafetería", "cafeteria", "café", "кафе"],
      canonical: "coffee shop",
      expansions: ["cafe interior", "barista making coffee", "coffee shop customers"]),
    PhraseRule(
      terms: [
        "city night", "城市夜景", "都市夜景", "夜の街", "도시 야경", "ciudad de noche", "cidade à noite",
        "ville de nuit", "stadt bei nacht", "ночной город",
      ],
      canonical: "city night",
      expansions: ["city skyline at night", "downtown night", "night traffic"]),
    PhraseRule(
      terms: [
        "factory worker", "工厂工人", "工廠工人", "工場労働者", "공장 노동자", "trabajador de fábrica",
        "operário de fábrica", "ouvrier d'usine", "fabrikarbeiter", "рабочий завода",
      ],
      canonical: "factory worker",
      expansions: ["industrial worker", "factory production line", "manufacturing worker"]),
    PhraseRule(
      terms: ["apollo 11", "阿波罗11号", "阿波羅11號", "アポロ11号", "아폴로 11호", "apolo 11", "аполлон-11"],
      canonical: "Apollo 11",
      expansions: ["Apollo 11 moon landing", "1969 moon landing", "Apollo mission archive footage"]),
    PhraseRule(
      terms: [
        "俄乌战争", "俄烏戰爭", "russia ukraine war", "guerra de ucrania", "guerra na ucrânia",
        "guerre en ukraine", "russland-ukraine-krieg", "российско-украинская война", "ロシア・ウクライナ戦争",
        "러시아-우크라이나 전쟁",
      ],
      canonical: "Russia Ukraine war",
      expansions: ["Russo-Ukrainian War", "Russian invasion of Ukraine", "Ukraine conflict"]),
    PhraseRule(
      terms: [
        "台湾美食", "台灣美食", "taiwan cuisine", "comida taiwanesa", "culinária taiwanesa",
        "cuisine taïwanaise", "taiwanesische küche", "тайваньская кухня", "台湾料理", "대만 음식",
      ],
      canonical: "Taiwan cuisine",
      expansions: ["Taiwan street food", "Taiwan night market food", "Taiwanese cooking"]),
    PhraseRule(
      terms: ["阿根廷", "argentina"], canonical: "Argentina", expansions: []),
    PhraseRule(
      terms: ["布宜诺斯艾利斯", "布宜諾斯艾利斯", "buenos aires"], canonical: "Buenos Aires", expansions: []),
    PhraseRule(
      terms: ["银行挤兑", "銀行擠兌", "bank run"], canonical: "bank run",
      expansions: ["bank queue", "bank withdrawal queue"]),
    PhraseRule(
      terms: ["经济危机", "經濟危機", "economic crisis"], canonical: "economic crisis",
      expansions: ["financial crisis"]),
    PhraseRule(
      terms: ["城市", "都市", "city", "ciudad", "cidade", "ville", "stadt", "город", "都市", "도시"],
      canonical: "city", expansions: ["urban life"]),
    PhraseRule(
      terms: ["工厂", "工廠", "factory", "fábrica", "usine", "fabrik", "завод", "工場", "공장"],
      canonical: "factory", expansions: ["manufacturing", "production line"]),
  ]

  static func containsChinese(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
  }

  static func keywords(
    for original: String, translated: String? = nil, smartExpansion: Bool = true,
    interfaceLanguage: AppLanguage = .english
  ) -> [SearchKeyword] {
    MultilingualQueryEngine.plan(
      for: original, interfaceLanguage: interfaceLanguage,
      translatedSupplement: translated, includeVisualExpansions: smartExpansion
    ).keywords
  }

  static func providerKeywordPlan(
    from keywords: [SearchKeyword], provider: ProviderID, mode: ProviderMode
  ) -> [SearchKeyword] {
    let enabled = keywords.filter {
      $0.isEnabled && !$0.text.cleanQuery.isEmpty
    }
    guard !enabled.isEmpty else { return [] }
    if mode == .limited { return [enabled[0]] }

    return enabled.prefix(14).map { $0 }
  }

  static func providerQueries(
    from keywords: [SearchKeyword], provider: ProviderID, mode: ProviderMode
  ) -> [String] {
    providerKeywordPlan(from: keywords, provider: provider, mode: mode).map(\.text)
  }

  static func queryBudget(provider: ProviderID, mode: ProviderMode) -> Int {
    if mode == .limited { return 1 }
    return 14
  }

  static func mergeTranslation(_ translation: String, into keywords: [SearchKeyword])
    -> [SearchKeyword]
  {
    let translated = translation.cleanQuery
    guard !translated.isEmpty else { return keywords }
    var result = keywords
    if !result.contains(where: { $0.text.caseInsensitiveCompare(translated) == .orderedSame }) {
      let fallback = result.first(where: { $0.origin == .input })?.language ?? .english
      result.append(
        SearchKeyword(
          text: translated,
          language: MultilingualQueryEngine.detectLanguage(in: translated, fallback: fallback),
          origin: .systemTranslation, priority: 2))
    }
    return Array(result.prefix(14))
  }

  static func splitScript(_ script: String) -> [String] {
    let normalized = script.replacingOccurrences(of: "\r\n", with: "\n")
    let separated = normalized.replacingOccurrences(
      of: "\\n\\s*\\n", with: "\n\u{0000}\n", options: .regularExpression)
    let paragraphs = separated.components(separatedBy: "\u{0000}")
    var output: [String] = []
    for paragraph in paragraphs {
      let clean = paragraph.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard !clean.isEmpty else { continue }
      let sentences = clean.split(whereSeparator: { "。！？!?；;".contains($0) }).map {
        String($0).trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
      var buffer = ""
      for sentence in sentences {
        if buffer.count + sentence.count <= 80 {
          buffer += (buffer.isEmpty ? "" : "。") + sentence
        } else {
          if !buffer.isEmpty { output.append(buffer + "。") }
          buffer = sentence
        }
      }
      if !buffer.isEmpty { output.append(buffer + (buffer.hasSuffix("。") ? "" : "。")) }
    }
    return output
  }

  private static func years(in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "(?:18|19|20)\\d{2}") else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return regex.matches(in: value, range: range).compactMap {
      Range($0.range, in: value).map { String(value[$0]) }
    }
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
      seen.insert($0.folding(options: .diacriticInsensitive, locale: .current).lowercased())
        .inserted
    }
  }
}

extension String {
  fileprivate var cleanQuery: String {
    String(prefix(120)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

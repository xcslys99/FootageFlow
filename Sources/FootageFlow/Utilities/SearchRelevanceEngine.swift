import Foundation

struct SearchConceptGroup: Codable, Hashable, Sendable {
  let id: String
  let label: String
  let aliases: [String]
}

struct SearchIntent: Codable, Hashable, Sendable {
  let originalQuery: String
  let conceptGroups: [SearchConceptGroup]
}

struct RelevanceAssessment: Codable, Hashable, Sendable {
  let score: Double
  let coveredGroupIDs: [String]
  let totalGroupCount: Int
  let eligible: Bool

  var coverageRatio: Double {
    guard totalGroupCount > 0 else { return 0 }
    return Double(coveredGroupIDs.count) / Double(totalGroupCount)
  }
}

/// Shared, deterministic second-stage ranker used by both the macOS app and Windows core host.
/// It deliberately uses source metadata only; the query sent to a provider cannot by itself make
/// an item relevant.
enum SearchRelevanceEngine {
  private struct ConceptRule: Sendable {
    let id: String
    let label: String
    let aliases: [String]
  }

  private struct WeightedField: Sendable {
    let text: String
    let weight: Double
    let countsForCoverage: Bool
  }

  private static let rules: [ConceptRule] = [
    ConceptRule(
      id: "place.taiwan", label: "Taiwan",
      aliases: [
        "台湾", "台灣", "taiwan", "taiwanese", "taiwanesa", "taiwanês", "taiwanaise",
        "taiwanesische", "taipei", "台北", "臺北", "taïwan",
      ]),
    ConceptRule(
      id: "place.guangzhou", label: "Guangzhou",
      aliases: [
        "广州", "廣州", "guangzhou", "canton", "cantonese", "cantón", "cantão", "kanton",
        "広州", "광저우", "гуанчжоу",
      ]),
    ConceptRule(
      id: "place.japan", label: "Japan",
      aliases: ["日本", "japan", "japanese", "tokyo", "東京", "东京", "japon", "japón", "japao", "japão"]),
    ConceptRule(
      id: "place.france", label: "France",
      aliases: ["法国", "法國", "france", "french", "paris", "français", "francaise", "französisch"]),
    ConceptRule(
      id: "place.argentina", label: "Argentina",
      aliases: ["阿根廷", "argentina", "argentine", "buenos aires", "布宜诺斯艾利斯", "布宜諾斯艾利斯"]),
    ConceptRule(
      id: "place.russia-ukraine", label: "Russia and Ukraine",
      aliases: [
        "俄乌", "俄烏", "russia ukraine", "russian ukrainian", "russo ukrainian", "ukraine",
        "украин", "российско украин", "ロシア ウクライナ", "러시아 우크라이나",
      ]),
    ConceptRule(
      id: "topic.food", label: "Food",
      aliases: [
        "美食", "料理", "食物", "小吃", "夜市", "餐厅", "餐廳", "烹饪", "烹飪", "菜肴",
        "饮食", "飲食", "食品", "food", "foods", "cuisine", "culinary", "cooking", "cook",
        "dish", "dishes", "recipe", "recipes", "restaurant", "restaurants", "street food",
        "snack", "snacks", "meal", "meals", "noodle", "noodles", "soup", "chicken", "pork",
        "beef", "rice", "dumpling", "dumplings", "dim sum", "yum cha", "seafood", "kitchen",
        "comida", "cocina", "culinaria",
        "culinária", "delicacies", "gastronomy", "gastronomía", "gastronomie", "küche",
        "粤菜", "粵菜", "早茶", "点心", "點心", "飲茶", "еда", "кухня", "음식", "요리",
      ]),
    ConceptRule(
      id: "topic.city", label: "City",
      aliases: [
        "城市", "都市", "city", "cities", "urban", "downtown", "skyline", "ciudad", "cidade", "ville",
        "stadt", "город", "도시",
      ]),
    ConceptRule(
      id: "topic.night", label: "Night",
      aliases: [
        "夜", "夜景", "夜晚", "night", "nighttime", "evening", "after dark", "dusk", "noche", "noite",
        "nuit", "nacht", "ноч", "야경", "밤",
      ]),
    ConceptRule(
      id: "topic.factory", label: "Factory",
      aliases: [
        "工厂", "工廠", "factory", "factories", "industrial", "manufacturing", "production line",
        "assembly line", "fábrica", "usine", "fabrik", "завод", "工場", "공장",
      ]),
    ConceptRule(
      id: "topic.worker", label: "Worker",
      aliases: [
        "工人", "劳工", "勞工", "worker", "workers", "laborer", "labourer", "employee", "workforce",
        "operator", "trabajador", "operário", "ouvrier", "arbeiter", "рабоч", "労働者", "노동자",
      ]),
    ConceptRule(
      id: "topic.burger", label: "Hamburger",
      aliases: [
        "汉堡", "漢堡", "hamburger", "hamburgers", "burger", "burgers", "cheeseburger", "ハンバーガー", "햄버거",
        "hamburguesa", "hambúrguer",
      ]),
    ConceptRule(
      id: "event.apollo11", label: "Apollo 11",
      aliases: [
        "apollo 11", "apollo eleven", "阿波罗11号", "阿波羅11號", "アポロ11号", "아폴로 11호", "apolo 11",
        "аполлон 11", "1969 moon landing",
      ]),
    ConceptRule(
      id: "topic.conflict", label: "War or conflict",
      aliases: [
        "战争", "戰爭", "冲突", "衝突", "入侵", "war", "warfare", "conflict", "invasion", "battle", "combat",
        "military", "troops", "guerra", "guerre", "krieg", "войн", "戦争", "전쟁",
      ]),
    ConceptRule(
      id: "topic.finance-crisis", label: "Financial crisis",
      aliases: [
        "银行挤兑", "銀行擠兌", "bank run", "bank queue", "economic crisis", "financial crisis", "经济危机",
        "經濟危機", "withdrawal queue",
      ]),
    ConceptRule(
      id: "topic.protest", label: "Protest",
      aliases: [
        "抗议", "抗議", "protest", "protests", "demonstration", "protesta", "protesto",
        "manifestation", "protest", "протест", "抗議活動", "시위",
      ]),
  ]

  private static let stopWords: Set<String> = [
    "a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to",
    "with", "footage", "video", "videos", "archive",
  ]

  private static let distractorSignals = [
    "news", "politics", "political", "election", "journalist", "journalism", "military",
    "troops", "naval", "exercise", "song", "songs", "music", "concert",
  ]

  private static let stricterProviders: Set<ProviderID> = [
    .peertube, .libraryOfCongress, .internetArchive, .youtube,
  ]

  static func intent(for query: String, supportingQueries: [String] = []) -> SearchIntent {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else {
      return SearchIntent(originalQuery: query, conceptGroups: [])
    }

    // Translated and expanded queries are retrieval hints only. They must never add a new
    // mandatory concept group that was not present in the user's original text.
    let semanticCorpus = normalizedQuery
    var groups: [SearchConceptGroup] = []
    var coveredTokens = Set<String>()
    for rule in rules where rule.aliases.contains(where: { contains($0, in: semanticCorpus) }) {
      groups.append(SearchConceptGroup(id: rule.id, label: rule.label, aliases: rule.aliases))
      for alias in rule.aliases {
        coveredTokens.formUnion(tokens(alias))
      }
    }

    if groups.isEmpty {
      let supportingAliases = supportingQueries.map(normalize).filter { !$0.isEmpty }
      return SearchIntent(
        originalQuery: query,
        conceptGroups: [
          SearchConceptGroup(
            id: "literal.query", label: query,
            aliases: unique(
              [normalizedQuery] + tokens(normalizedQuery) + supportingAliases
                + supportingAliases.flatMap(tokens)))
        ])
    }

    let literalSource = normalizedQuery
    let queryTokens = tokens(literalSource).filter {
      $0.count > 1 && !stopWords.contains($0) && !coveredTokens.contains($0)
        && !(hasCJK($0) && !groups.isEmpty)
    }
    for token in queryTokens.prefix(max(0, 4 - groups.count)) {
      let id = "literal.\(token)"
      guard !groups.contains(where: { $0.id == id }) else { continue }
      groups.append(SearchConceptGroup(id: id, label: token, aliases: literalAliases(token)))
    }

    return SearchIntent(originalQuery: query, conceptGroups: groups)
  }

  static func assess(
    _ asset: MediaAsset, intent: SearchIntent, mode: SearchRelevanceMode
  ) -> RelevanceAssessment {
    guard !intent.conceptGroups.isEmpty else {
      return RelevanceAssessment(
        score: max(0, asset.relevanceScore), coveredGroupIDs: [], totalGroupCount: 0,
        eligible: mode == .broad)
    }

    let metadata = asset.originalMetadata
    let tags = metadataText(
      metadata, keys: ["tags", "tag", "keywords", "keyword", "subjects", "subject", "topics"])
    let categories = metadataText(
      metadata,
      keys: ["category", "categories", "collection", "collections", "partOf", "originalFormat"])
    let matchedQuery = metadata["matchedQuery"] ?? asset.searchKeyword
    let syntheticTitle = metadata["syntheticTitle"] == "true"
    let trustedQueryFallback =
      syntheticTitle && asset.provider == .pexels
      && tags.isEmpty && categories.isEmpty && (asset.description ?? "").isEmpty
    let fields = [
      WeightedField(
        text: asset.title, weight: syntheticTitle ? 0 : 1.0,
        countsForCoverage: !syntheticTitle),
      WeightedField(text: tags, weight: 0.86, countsForCoverage: true),
      WeightedField(text: categories, weight: 0.74, countsForCoverage: true),
      WeightedField(text: asset.description ?? "", weight: 0.56, countsForCoverage: true),
      WeightedField(text: asset.creator ?? "", weight: 0.18, countsForCoverage: false),
      WeightedField(
        text: matchedQuery, weight: trustedQueryFallback ? 0.54 : 0.06,
        countsForCoverage: trustedQueryFallback),
    ].map {
      WeightedField(
        text: normalize($0.text), weight: $0.weight, countsForCoverage: $0.countsForCoverage)
    }

    var covered: [String] = []
    var groupScores: [Double] = []
    var titleCovered = 0
    var metadataCovered = 0
    for group in intent.conceptGroups {
      var best = 0.0
      var coverage = false
      for (index, field) in fields.enumerated() where !field.text.isEmpty {
        guard group.aliases.contains(where: { contains($0, in: field.text) }) else { continue }
        best = max(best, field.weight)
        if field.countsForCoverage {
          coverage = true
          if index == 0 { titleCovered += 1 }
          if index == 1 || index == 2 { metadataCovered += 1 }
        }
      }
      if coverage { covered.append(group.id) }
      groupScores.append(best)
    }

    let count = Double(intent.conceptGroups.count)
    let mean = groupScores.reduce(0, +) / count
    let providerSignal = min(max(asset.relevanceScore, 0), 1) * 0.07
    let titleBonus = Double(titleCovered) / count * 0.13
    let metadataBonus = Double(metadataCovered) / count * 0.07
    let originalPhrase = normalize(intent.originalQuery)
    let phraseBonus =
      !originalPhrase.isEmpty && contains(originalPhrase, in: fields[0].text) ? 0.12 : 0
    let score = min(1.4, mean + providerSignal + titleBonus + metadataBonus + phraseBonus)
    let coveredCount = covered.count
    let total = intent.conceptGroups.count
    let strictAdjustment = stricterProviders.contains(asset.provider) ? 0.04 : 0
    let coherenceWindow = stricterProviders.contains(asset.provider) ? 24 : 36
    let semanticCorpus = [fields[0].text, fields[1].text, fields[2].text, fields[3].text]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let strongCorpus = [fields[0].text, fields[1].text, fields[2].text]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let strongCoveredIDs = Set(
      intent.conceptGroups.filter { group in
        group.aliases.contains(where: { contains($0, in: strongCorpus) })
      }.map(\.id))
    let desiredPlaceIDs = Set(
      intent.conceptGroups.filter { $0.id.hasPrefix("place.") }.map(\.id))
    let conflictingPlaceInStrongMetadata =
      !desiredPlaceIDs.isEmpty
      && desiredPlaceIDs.isDisjoint(with: strongCoveredIDs)
      && rules.contains { rule in
        rule.id.hasPrefix("place.") && !desiredPlaceIDs.contains(rule.id)
          && rule.aliases.contains(where: { contains($0, in: strongCorpus) })
      }
    let weakTopicHasDistractor =
      intent.conceptGroups.contains {
        !$0.id.hasPrefix("place.") && !strongCoveredIDs.contains($0.id)
      }
      && distractorSignals.contains(where: { contains($0, in: strongCorpus) })
    let oversizedDescriptionOnlyMatch =
      stricterProviders.contains(asset.provider) && total > 1 && strongCoveredIDs.isEmpty
      && tokens(fields[3].text).count > 180
    let titleDescriptionCorpus = [fields[0].text, fields[3].text]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let verboseMetadataOnlyTopic =
      stricterProviders.contains(asset.provider)
      && tokens([fields[1].text, fields[2].text].joined(separator: " ")).count > 12
      && intent.conceptGroups.contains { group in
        !group.id.hasPrefix("place.")
          && !group.aliases.contains(where: { contains($0, in: titleDescriptionCorpus) })
      }
    let coherentCoverage =
      total <= 1
      || minimumConceptWindow(intent.conceptGroups, in: semanticCorpus).map {
        $0 <= coherenceWindow
      } == true
    let contextCompatible =
      !conflictingPlaceInStrongMetadata && !weakTopicHasDistractor
      && !oversizedDescriptionOnlyMatch && !verboseMetadataOnlyTopic

    let eligible: Bool
    switch mode {
    case .precise:
      eligible =
        coveredCount == total && groupScores.allSatisfy { $0 >= 0.74 }
        && coherentCoverage && contextCompatible && score >= 0.82 + strictAdjustment
    case .balanced:
      let required = total <= 2 ? total : Int(ceil(Double(total) * 0.67))
      eligible =
        coveredCount >= required && coherentCoverage && contextCompatible
        && score >= 0.52 + strictAdjustment
    case .broad:
      eligible = coveredCount >= 1 && score >= 0.18 + strictAdjustment / 2
    }
    return RelevanceAssessment(
      score: score, coveredGroupIDs: covered, totalGroupCount: total, eligible: eligible)
  }

  static func rank(
    _ assets: [MediaAsset], query: String, mode: SearchRelevanceMode,
    supportingQueries: [String] = [], inputLanguage: AppLanguage? = nil,
    interfaceLanguage: AppLanguage = .english
  ) -> [MediaAsset] {
    let searchIntent = intent(for: query, supportingQueries: supportingQueries)
    let detectedInput =
      inputLanguage
      ?? MultilingualQueryEngine.detectLanguage(in: query, fallback: interfaceLanguage)
    return assets.compactMap { asset -> MediaAsset? in
      let assessment = assess(asset, intent: searchIntent, mode: mode)
      guard assessment.eligible else { return nil }
      var ranked = asset
      let language = resultLanguage(
        for: asset, fallback: detectedInput, interfaceLanguage: interfaceLanguage)
      let languagePriority = MultilingualQueryEngine.languagePriority(
        language, input: detectedInput, interface: interfaceLanguage)
      let languageBonus: Double =
        switch languagePriority {
        case 0: 0.035
        case 1: 0.025
        case 2: 0.015
        default: 0
        }
      ranked.originalMetadata["providerRelevanceScore"] = String(asset.relevanceScore)
      ranked.originalMetadata["localRelevanceScore"] = String(assessment.score)
      ranked.originalMetadata["resultLanguage"] = language.rawValue
      ranked.originalMetadata["resultLanguagePriority"] = String(languagePriority)
      ranked.originalMetadata["conceptCoverage"] =
        "\(assessment.coveredGroupIDs.count)/\(assessment.totalGroupCount)"
      // Apply language only after semantic eligibility. It can break close ties but can never
      // rescue an item that failed the user's core concept groups.
      ranked.relevanceScore = assessment.score + languageBonus
      return ranked
    }.sorted {
      if $0.relevanceScore != $1.relevanceScore { return $0.relevanceScore > $1.relevanceScore }
      let leftProvider = Double($0.originalMetadata["providerRelevanceScore"] ?? "") ?? 0
      let rightProvider = Double($1.originalMetadata["providerRelevanceScore"] ?? "") ?? 0
      if leftProvider != rightProvider { return leftProvider > rightProvider }
      return $0.stableID < $1.stableID
    }
  }

  private static func resultLanguage(
    for asset: MediaAsset, fallback: AppLanguage, interfaceLanguage: AppLanguage
  ) -> AppLanguage {
    let metadataKeys = ["language", "languages", "lang", "contentLanguage"]
    for key in metadataKeys {
      guard
        let raw = asset.originalMetadata.first(where: {
          $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value.lowercased()
      else { continue }
      if let exact = AppLanguage.allCases.first(where: {
        raw == $0.rawValue.lowercased() || raw.hasPrefix($0.rawValue.lowercased() + "-")
      }) {
        return exact
      }
      if raw.contains("chinese") || raw.contains("中文") { return .simplifiedChinese }
      if raw.contains("english") { return .english }
      if raw.contains("spanish") { return .spanish }
      if raw.contains("portuguese") { return .brazilianPortuguese }
      if raw.contains("japanese") { return .japanese }
      if raw.contains("korean") { return .korean }
      if raw.contains("german") { return .german }
      if raw.contains("french") { return .french }
      if raw.contains("russian") { return .russian }
    }
    let visible = [asset.title, asset.description ?? ""].joined(separator: " ")
    let detected = MultilingualQueryEngine.detectLanguage(in: visible, fallback: fallback)
    if detected != fallback || visible.unicodeScalars.contains(where: { $0.value > 127 }) {
      return detected
    }
    if let raw = asset.originalMetadata["matchedQueryLanguage"],
      let matched = AppLanguage(rawValue: raw)
    {
      return matched
    }
    return MultilingualQueryEngine.detectLanguage(in: visible, fallback: interfaceLanguage)
  }

  private static func metadataText(_ metadata: [String: String], keys: [String]) -> String {
    let wanted = Set(keys.map { $0.lowercased() })
    return metadata.compactMap { key, value in
      wanted.contains(key.lowercased()) ? value : nil
    }.joined(separator: " ")
  }

  private static func literalAliases(_ token: String) -> [String] {
    var result = [token]
    if token.count > 3 && token.hasSuffix("s") { result.append(String(token.dropLast())) }
    if token.count > 3 && !token.hasSuffix("s") { result.append(token + "s") }
    return unique(result)
  }

  private static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
    .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func tokens(_ value: String) -> [String] {
    normalize(value).split(separator: " ").map(String.init)
  }

  private static func hasCJK(_ value: String) -> Bool {
    value.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) }
  }

  private static func contains(_ rawNeedle: String, in normalizedHaystack: String) -> Bool {
    let needle = normalize(rawNeedle)
    guard !needle.isEmpty, !normalizedHaystack.isEmpty else { return false }
    if hasCJK(needle) {
      return normalizedHaystack.contains(needle)
    }
    return " \(normalizedHaystack) ".contains(" \(needle) ")
  }

  /// Returns the smallest token window containing at least one alias from every concept group.
  /// This prevents unrelated items with long archive descriptions from passing merely because
  /// separate list entries happen to mention each concept far apart.
  private static func minimumConceptWindow(
    _ groups: [SearchConceptGroup], in normalizedText: String
  ) -> Int? {
    if hasCJK(normalizedText),
      groups.allSatisfy({ group in
        group.aliases.contains(where: { contains($0, in: normalizedText) })
      })
    {
      return 1
    }
    let haystack = tokens(normalizedText)
    guard !haystack.isEmpty, !groups.isEmpty else { return nil }

    struct Hit {
      let start: Int
      let end: Int
      let groupIndex: Int
    }
    var hits: [Hit] = []
    for (groupIndex, group) in groups.enumerated() {
      for alias in group.aliases {
        let needle = tokens(alias)
        guard !needle.isEmpty, needle.count <= haystack.count else { continue }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
          hits.append(
            Hit(start: start, end: start + needle.count - 1, groupIndex: groupIndex))
        }
      }
    }
    hits.sort {
      $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
    }
    guard Set(hits.map(\.groupIndex)).count == groups.count else { return nil }

    var counts = Array(repeating: 0, count: groups.count)
    var coveredGroups = 0
    var left = 0
    var best: Int?
    for right in hits.indices {
      let rightHit = hits[right]
      if counts[rightHit.groupIndex] == 0 { coveredGroups += 1 }
      counts[rightHit.groupIndex] += 1
      while coveredGroups == groups.count && left <= right {
        let span = rightHit.end - hits[left].start + 1
        best = min(best ?? span, span)
        let leftHit = hits[left]
        counts[leftHit.groupIndex] -= 1
        if counts[leftHit.groupIndex] == 0 { coveredGroups -= 1 }
        left += 1
      }
    }
    return best
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert(normalize($0)).inserted }
  }
}

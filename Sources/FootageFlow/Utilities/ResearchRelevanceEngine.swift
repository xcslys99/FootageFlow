import Foundation

/// Research records use the exact same query intent as media search, but their
/// fields differ. This small adapter preserves concept coverage without
/// pretending a discovery result is downloadable media.
enum ResearchRelevanceEngine {
  static func rank(
    _ records: [ResearchRecord], query: String, mode: SearchRelevanceMode,
    supportingQueries: [String], inputLanguage: AppLanguage, interfaceLanguage: AppLanguage
  ) -> [ResearchRecord] {
    let intent = SearchRelevanceEngine.intent(for: query, supportingQueries: supportingQueries)
    return records.compactMap { record in
      let text = normalize(
        [
          record.title, record.summary ?? "", record.authors.joined(separator: " "),
          record.providerMetadata.values.joined(separator: " "), record.searchKeyword,
        ].joined(separator: " "))
      let title = normalize(record.title)
      let groups = intent.conceptGroups
      let covered = groups.filter { group in
        group.aliases.contains { alias in contains(alias, in: text) }
      }
      guard !groups.isEmpty else { return record }
      let titleCovered = groups.filter { group in
        group.aliases.contains { alias in contains(alias, in: title) }
      }.count
      let coverage = Double(covered.count) / Double(groups.count)
      let languageBonus: Double = {
        guard let language = record.language else { return 0 }
        return
          switch MultilingualQueryEngine.languagePriority(
            language, input: inputLanguage, interface: interfaceLanguage
          )
        {
        case 0: 0.035
        case 1: 0.025
        case 2: 0.015
        default: 0
        }
      }()
      let score =
        coverage * 0.78 + Double(titleCovered) / Double(groups.count) * 0.14
        + min(max(record.relevanceScore, 0), 1) * 0.08 + languageBonus
      let eligible: Bool
      switch mode {
      case .precise: eligible = covered.count == groups.count && score >= 0.74
      case .balanced:
        eligible =
          covered.count
          >= (groups.count <= 2 ? groups.count : Int(ceil(Double(groups.count) * 0.67)))
          && score >= 0.48
      case .broad: eligible = !covered.isEmpty && score >= 0.16
      }
      guard eligible else { return nil }
      var value = record
      value.relevanceScore = score
      value.providerMetadata["conceptCoverage"] = "\(covered.count)/\(groups.count)"
      return value
    }.sorted { $0.relevanceScore > $1.relevanceScore }
  }

  private static func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }

  private static func contains(_ alias: String, in text: String) -> Bool {
    let needle = normalize(alias)
    guard !needle.isEmpty else { return false }
    if needle.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
      return text.contains(needle)
    }
    return text.range(
      of: "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b", options: .regularExpression)
      != nil
      || text.contains(needle)
  }
}

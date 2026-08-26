import Foundation

/// Preserves the meaningful part of a compound query that is not yet represented
/// by the curated concept lexicon. This is deliberately local and deterministic:
/// an unknown place or proper noun must narrow a search, never be discarded and
/// turned into a broad subject-only request.
enum QueryIntentPreserver {
  private static let connectorWords: Set<String> = [
    "a", "an", "and", "at", "bei", "by", "da", "de", "del", "des", "di", "do", "e",
    "en", "et", "for", "from", "in", "la", "le", "les", "na", "of", "on", "para", "the",
    "to", "und", "with", "y", "и",
  ]

  static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
    .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func containsCJK(_ value: String) -> Bool {
    value.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) }
  }

  /// Returns non-empty query fragments left after known concept aliases are
  /// removed. For example, "西安美食" minus the food aliases becomes "西安".
  static func residuals(in value: String, removing aliases: [String]) -> [String] {
    var remaining = normalized(value)
    guard !remaining.isEmpty else { return [] }

    var normalizedAliases: [String] = []
    for alias in aliases {
      let normalizedAlias = normalized(alias)
      if !normalizedAlias.isEmpty { normalizedAliases.append(normalizedAlias) }
    }
    normalizedAliases.sort { left, right in
      left.count == right.count ? left < right : left.count > right.count
    }
    for alias in normalizedAliases {
      if containsCJK(alias) {
        remaining = remaining.replacingOccurrences(of: alias, with: " ")
      } else {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
        remaining = remaining.replacingOccurrences(
          of: pattern, with: " ", options: .regularExpression)
      }
    }

    return remaining.split(separator: " ").map(String.init).filter { fragment in
      fragment.count > 1 && !connectorWords.contains(fragment)
        && !fragment.allSatisfy { $0.isNumber }
    }
  }

  static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
      let key = normalized($0)
      return !key.isEmpty && seen.insert(key).inserted
    }
  }
}

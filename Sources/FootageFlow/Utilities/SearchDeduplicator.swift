import Foundation

enum ResearchRecordDeduplicator {
  static func apply(_ records: [ResearchRecord]) -> [ResearchRecord] {
    var seen = Set<String>()
    return records.filter { record in
      let canonical =
        URLCanonicalizer.canonical(record.canonicalURL) ?? record.canonicalURL.absoluteString
      let key: String
      if let doi = record.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty {
        key = "doi:\(doi.lowercased())"
      } else if let qid = record.wikidataQID?.uppercased(), !qid.isEmpty {
        key = "qid:\(qid)"
      } else {
        key = "\(record.provider.rawValue):\(record.sourceNativeID ?? canonical)"
      }
      return seen.insert(key).inserted
    }
  }
}

enum SearchDeduplicator {
  static func apply(_ input: [MediaAsset]) -> [MediaAsset] {
    var stable = Set<String>()
    // Repeated query hits for one native asset are one result. Cross-provider URLs
    // are retained for the user's duplicate review instead of silently discarded.
    return input.filter { stable.insert($0.stableID).inserted }
  }
}

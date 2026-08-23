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
    var sources = Set<String>()
    var downloads = Set<String>()
    return input.filter { asset in
      let source = asset.sourcePageURL.absoluteString
      let download = asset.downloadURL?.absoluteString
      guard stable.insert(asset.stableID).inserted, sources.insert(source).inserted else {
        return false
      }
      if let download, !downloads.insert(download).inserted { return false }
      return true
    }
  }
}

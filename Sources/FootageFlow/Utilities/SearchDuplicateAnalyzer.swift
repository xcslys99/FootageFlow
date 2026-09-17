import Foundation

/// Shared evidence rules for both project and search-result duplicate review.
enum DuplicateEvidenceNormalizer {
  static func folded(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func tokens(_ value: String) -> Set<String> {
    let ignored: Set<String> = [
      "a", "an", "and", "the", "of", "in", "on", "for", "video", "clip", "footage", "stock",
    ]
    return Set(
      folded(value).split(separator: " ").map(String.init).filter {
        ($0.count > 1 || $0.allSatisfy(\.isNumber)) && !ignored.contains($0)
      })
  }

  static func canonical(_ value: URL?) -> String? { URLCanonicalizer.canonical(value) }
}

enum SearchDuplicateConfidence: String, Codable, Sendable {
  case exact, likely, possible

  var label: String {
    switch self {
    case .exact: tr("duplicate.exact")
    case .likely: tr("duplicate.likely")
    case .possible: tr("duplicate.possible")
    }
  }
}

struct SearchDuplicateGroup: Codable, Sendable, Identifiable {
  let id: String
  let memberIDs: [String]
  let recommendedID: String
  let confidence: SearchDuplicateConfidence
  let evidence: [String]
}

struct SearchDuplicateEntry: Codable, Sendable, Identifiable {
  let id: String
  let memberIDs: [String]
  let recommendedID: String
  let confidence: SearchDuplicateConfidence?
  var isGroup: Bool { memberIDs.count > 1 }
}

struct SearchDuplicateReview: Codable, Sendable {
  let resultCount: Int
  let uniqueCount: Int
  let groups: [SearchDuplicateGroup]
  let entries: [SearchDuplicateEntry]
  let thumbnailCandidateIDs: [String]

  static func ungrouped(_ assets: [MediaAsset]) -> Self {
    let entries = assets.map {
      SearchDuplicateEntry(
        id: $0.stableID, memberIDs: [$0.stableID], recommendedID: $0.stableID,
        confidence: nil)
    }
    return Self(
      resultCount: assets.count, uniqueCount: assets.count, groups: [], entries: entries,
      thumbnailCandidateIDs: [])
  }
}

/// Conservative, indexed analysis. It never mutates or removes a source asset.
enum SearchDuplicateAnalyzer {
  private struct Candidate {
    let asset: MediaAsset
    let title: Set<String>
    let creator: String
    let filename: String
    let durationBand: Int
  }

  static func analyze(
    _ assets: [MediaAsset], thumbnailHashes: [String: UInt64] = [:],
    isCancelled: () -> Bool = { false }
  ) -> SearchDuplicateReview {
    guard assets.count > 1, !isCancelled() else { return .ungrouped(assets) }
    let candidates = assets.map { asset in
      Candidate(
        asset: asset, title: DuplicateEvidenceNormalizer.tokens(asset.title),
        creator: DuplicateEvidenceNormalizer.folded(asset.creator ?? ""),
        filename: DuplicateEvidenceNormalizer.folded(
          asset.downloadURL?.deletingPathExtension().lastPathComponent ?? ""),
        durationBand: asset.duration.map { Int($0 / 2) } ?? -1)
    }
    var parent = Array(candidates.indices)
    var rank = Array(repeating: 0, count: candidates.count)
    var weakest = Array(repeating: SearchDuplicateConfidence.exact, count: candidates.count)
    var reasons: [Int: Set<String>] = [:]

    func root(_ index: Int) -> Int {
      var position = index
      while parent[position] != position { position = parent[position] }
      var cursor = index
      while parent[cursor] != cursor {
        let next = parent[cursor]
        parent[cursor] = position
        cursor = next
      }
      return position
    }

    func connect(
      _ left: Int, _ right: Int, _ confidence: SearchDuplicateConfidence, _ reason: String
    ) {
      var first = root(left)
      var second = root(right)
      guard first != second else { return }
      if rank[first] < rank[second] { swap(&first, &second) }
      parent[second] = first
      if rank[first] == rank[second] { rank[first] += 1 }
      weakest[first] = minimum(weakest[first], minimum(weakest[second], confidence))
      reasons[first, default: []].formUnion(reasons[second] ?? [])
      reasons[first, default: []].insert(reason)
      reasons[second] = nil
    }

    // Exact evidence is indexed, not pairwise compared.
    var exactIndex: [String: Int] = [:]
    for index in candidates.indices {
      if isCancelled() { return .ungrouped(assets) }
      let asset = candidates[index].asset
      let kind = asset.mediaType.rawValue
      let keys: [(String, String)] = [
        ("provider:\(asset.provider.rawValue):\(asset.id):\(kind)", "providerID"),
        (
          DuplicateEvidenceNormalizer.canonical(asset.sourcePageURL).map { "source:\($0):\(kind)" }
            ?? "",
          "sourceURL"
        ),
        (
          DuplicateEvidenceNormalizer.canonical(asset.downloadURL).map { "download:\($0):\(kind)" }
            ?? "",
          "downloadURL"
        ),
        (
          asset.originalMetadata["canonicalMediaID"].flatMap {
            let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : "media:\(normalized):\(kind)"
          } ?? "", "mediaID"
        ),
      ]
      for (key, reason) in keys where !key.isEmpty {
        if let other = exactIndex[key] {
          connect(other, index, .exact, reason)
        } else {
          exactIndex[key] = index
        }
      }
    }

    // Duration + uncommon title-token buckets keep comparisons bounded for large result sets.
    var tokenIndex: [String: [Int]] = [:]
    for index in candidates.indices {
      if isCancelled() { return .ungrouped(assets) }
      let candidate = candidates[index]
      var possible = Set<Int>()
      let bands =
        candidate.durationBand < 0
        ? [-1] : [candidate.durationBand - 1, candidate.durationBand, candidate.durationBand + 1]
      let anchors = candidate.title.sorted {
        $0.count == $1.count ? $0 < $1 : $0.count > $1.count
      }.prefix(10)
      for token in anchors {
        for band in bands {
          let key = "\(band):\(token)"
          if let bucket = tokenIndex[key], bucket.count <= 64 { possible.formUnion(bucket) }
        }
      }
      for other in possible.sorted() where root(other) != root(index) {
        if let confidence = metadataConfidence(candidate, candidates[other]) {
          connect(other, index, confidence, "metadata")
        }
      }
      for token in anchors {
        tokenIndex["\(candidate.durationBand):\(token)", default: []].append(index)
      }
    }

    // dHash bands can connect a differently titled transcode only with corroborating facts.
    var hashIndex: [String: [Int]] = [:]
    for index in candidates.indices {
      if isCancelled() { return .ungrouped(assets) }
      guard let hash = thumbnailHashes[candidates[index].asset.stableID] else { continue }
      var possible = Set<Int>()
      for band in 0..<8 {
        let key = "\(band):\((hash >> (band * 8)) & 0xff)"
        if let bucket = hashIndex[key], bucket.count <= 64 { possible.formUnion(bucket) }
      }
      for other in possible.sorted() where root(other) != root(index) {
        guard let otherHash = thumbnailHashes[candidates[other].asset.stableID],
          (hash ^ otherHash).nonzeroBitCount <= 4,
          durationCompatible(candidates[index].asset.duration, candidates[other].asset.duration)
        else { continue }
        let overlap = similarity(candidates[index].title, candidates[other].title)
        let sameCreator =
          !candidates[index].creator.isEmpty
          && candidates[index].creator == candidates[other].creator
        if overlap >= 0.35 || sameCreator { connect(other, index, .likely, "thumbnail") }
      }
      for band in 0..<8 {
        hashIndex["\(band):\((hash >> (band * 8)) & 0xff)", default: []].append(index)
      }
    }

    var components: [Int: [Int]] = [:]
    for index in candidates.indices { components[root(index), default: []].append(index) }
    var groups: [SearchDuplicateGroup] = []
    var byMember: [String: SearchDuplicateGroup] = [:]
    for (component, indices) in components where indices.count > 1 {
      let ids = indices.map { candidates[$0].asset.stableID }
      let recommended =
        indices.max {
          recommendationScore(candidates[$0].asset) < recommendationScore(candidates[$1].asset)
        } ?? indices[0]
      let group = SearchDuplicateGroup(
        id: groupID(ids), memberIDs: ids,
        recommendedID: candidates[recommended].asset.stableID,
        confidence: weakest[component], evidence: (reasons[component] ?? []).sorted())
      groups.append(group)
      for id in ids { byMember[id] = group }
    }
    var firstIndexByID: [String: Int] = [:]
    for (index, asset) in assets.enumerated() {
      if firstIndexByID[asset.stableID] == nil { firstIndexByID[asset.stableID] = index }
    }
    groups.sort {
      (firstIndexByID[$0.memberIDs[0]] ?? 0) < (firstIndexByID[$1.memberIDs[0]] ?? 0)
    }
    var seen = Set<String>()
    var entries: [SearchDuplicateEntry] = []
    for asset in assets {
      if let group = byMember[asset.stableID] {
        guard seen.insert(group.id).inserted else { continue }
        entries.append(
          SearchDuplicateEntry(
            id: group.id, memberIDs: group.memberIDs,
            recommendedID: group.recommendedID, confidence: group.confidence))
      } else {
        entries.append(
          SearchDuplicateEntry(
            id: asset.stableID, memberIDs: [asset.stableID],
            recommendedID: asset.stableID, confidence: nil))
      }
    }
    return SearchDuplicateReview(
      resultCount: assets.count, uniqueCount: entries.count,
      groups: groups, entries: entries,
      thumbnailCandidateIDs: thumbnailCandidates(assets))
  }

  /// Only visually compare plausible candidates; never fetch full media for review.
  private static func thumbnailCandidates(_ assets: [MediaAsset]) -> [String] {
    var buckets: [String: [String]] = [:]
    for asset in assets where !asset.effectiveThumbnailCandidates.isEmpty {
      let creator = DuplicateEvidenceNormalizer.folded(asset.creator ?? "")
      guard !creator.isEmpty else { continue }
      let duration = asset.duration.map { Int($0.rounded() / 2) } ?? -1
      buckets["\(creator)|\(duration)|\(asset.mediaType.rawValue)", default: []]
        .append(asset.stableID)
    }
    let eligible = buckets.values.filter { (2...16).contains($0.count) }
    let ids = Set(eligible.flatMap { $0 })
    // Network work is intentionally bounded independently from the synchronous scan.
    return Array(assets.lazy.map(\.stableID).filter(ids.contains).prefix(80))
  }

  private static func minimum(
    _ first: SearchDuplicateConfidence, _ second: SearchDuplicateConfidence
  ) -> SearchDuplicateConfidence {
    let order: [SearchDuplicateConfidence: Int] = [.exact: 2, .likely: 1, .possible: 0]
    return (order[first] ?? 0) <= (order[second] ?? 0) ? first : second
  }

  private static func metadataConfidence(_ first: Candidate, _ second: Candidate)
    -> SearchDuplicateConfidence?
  {
    guard first.asset.mediaType == second.asset.mediaType,
      durationCompatible(first.asset.duration, second.asset.duration)
    else { return nil }
    if !first.creator.isEmpty && !second.creator.isEmpty && first.creator != second.creator {
      return nil
    }
    let overlap = similarity(first.title, second.title)
    let sameCreator = !first.creator.isEmpty && first.creator == second.creator
    let sameFilename = first.filename.count >= 8 && first.filename == second.filename
    if overlap >= 0.72, first.asset.duration != nil, second.asset.duration != nil,
      sameCreator || sameFilename
    {
      return .likely
    }
    if overlap >= 0.88, first.asset.duration != nil,
      second.asset.duration != nil
    {
      return .possible
    }
    return nil
  }

  private static func durationCompatible(_ first: Double?, _ second: Double?) -> Bool {
    guard let first, let second else { return true }
    guard first.isFinite, second.isFinite, first >= 0, second >= 0 else { return false }
    return abs(first - second) <= max(1.5, min(first, second) * 0.04)
  }

  private static func similarity(_ first: Set<String>, _ second: Set<String>) -> Double {
    guard !first.isEmpty, !second.isEmpty else { return 0 }
    return Double(first.intersection(second).count) / Double(first.union(second).count)
  }

  private static func recommendationScore(_ asset: MediaAsset) -> Int {
    var score = 0
    if asset.effectiveRightsInfo.known { score += 3 }
    if asset.licenseURL != nil { score += 2 }
    if asset.creator?.isEmpty == false { score += 1 }
    if asset.isDirectlyDownloadable { score += 2 }
    if asset.previewURL != nil { score += 1 }
    if asset.duration != nil { score += 1 }
    score += min(3, ((asset.width ?? 0) * (asset.height ?? 0)) / 900_000)
    return score
  }

  private static func groupID(_ ids: [String]) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in ids.sorted().joined(separator: "|").utf8 {
      hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

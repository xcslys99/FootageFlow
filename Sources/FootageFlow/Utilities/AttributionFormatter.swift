import Foundation

enum AttributionFormatter {
  static func source(for asset: MediaAsset) -> String {
    var lines = [
      "\(tr("attribution.title")): \(asset.title)",
      "\(tr("attribution.provider")): \(asset.sourceDisplayName)",
    ]
    if let creator = clean(asset.creator) {
      lines.append("\(tr("attribution.creator")): \(creator)")
    }
    if let date = asset.publishedDate {
      lines.append("\(tr("attribution.date")): \(date.formatted(.iso8601.year().month().day()))")
    }
    lines.append("\(tr("attribution.originalURL")): \(asset.sourcePageURL.absoluteString)")
    return lines.joined(separator: "\n")
  }

  static func attribution(for asset: MediaAsset) -> String {
    var lines = [
      "\(tr("attribution.title")): \(asset.title)",
      "\(tr("attribution.creator")): \(clean(asset.creator) ?? tr("common.notProvided"))",
      "\(tr("attribution.source")): \(asset.sourceDisplayName)",
      "\(tr("attribution.originalURL")): \(asset.sourcePageURL.absoluteString)",
    ]
    let rights = asset.effectiveRightsInfo
    let rightsText =
      clean(rights.statement) ?? rights.uri?.absoluteString
      ?? tr("attribution.rightsUnknown")
    lines.append("\(tr("attribution.rights")): \(rightsText)")
    if let uri = rights.uri, clean(rights.statement) != nil {
      lines.append("\(tr("attribution.rightsURL")): \(uri.absoluteString)")
    }
    return lines.joined(separator: "\n")
  }

  static func sources(for assets: [MediaAsset]) -> String {
    assets.map(source).joined(separator: "\n\n---\n\n")
  }

  private static func clean(_ text: String?) -> String? {
    text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }
}

struct AssetSelection: Sendable {
  private(set) var stableIDs = Set<String>()

  var count: Int { stableIDs.count }
  func contains(_ asset: MediaAsset) -> Bool { stableIDs.contains(asset.stableID) }

  mutating func toggle(_ asset: MediaAsset) {
    if stableIDs.contains(asset.stableID) {
      stableIDs.remove(asset.stableID)
    } else {
      stableIDs.insert(asset.stableID)
    }
  }

  mutating func selectVisible(_ assets: [MediaAsset]) {
    stableIDs.formUnion(assets.map(\.stableID))
  }

  mutating func clear() { stableIDs.removeAll() }

  mutating func retainAvailable(_ assets: [MediaAsset]) {
    stableIDs.formIntersection(Set(assets.map(\.stableID)))
  }
}

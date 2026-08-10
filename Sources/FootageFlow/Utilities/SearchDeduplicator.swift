import Foundation

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

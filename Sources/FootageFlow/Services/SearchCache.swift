import CryptoKit
import Foundation

actor SearchCache {
  static let shared = SearchCache()
  private let directory: URL

  init() {
    directory = PlatformPaths.cache.appendingPathComponent("SearchResults", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func assets(provider: ProviderID, request: SearchRequest) -> [MediaAsset]? {
    guard case .allowed(let ttl) = ProviderPolicy.cachePolicy(for: provider) else { return nil }
    let url = fileURL(provider: provider, request: request)
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let modified = attributes[.modificationDate] as? Date
    else { return nil }
    guard Date().timeIntervalSince(modified) < ttl, let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode([MediaAsset].self, from: data)
  }

  func store(_ assets: [MediaAsset], provider: ProviderID, request: SearchRequest) {
    guard case .allowed = ProviderPolicy.cachePolicy(for: provider) else { return }
    guard let data = try? JSONEncoder().encode(assets) else { return }
    try? data.write(to: fileURL(provider: provider, request: request), options: .atomic)
  }

  func clear() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func fileURL(provider: ProviderID, request: SearchRequest) -> URL {
    let raw =
      "\(provider.rawValue)|\(request.query)|\(request.mediaType.rawValue)|\(request.orientation.rawValue)|\(request.resolution.rawValue)|\(request.duration.rawValue)|\(request.yearFrom.map(String.init) ?? "")|\(request.yearTo.map(String.init) ?? "")|\(request.downloadableOnly)"
    let hash = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(hash).appendingPathExtension("json")
  }
}

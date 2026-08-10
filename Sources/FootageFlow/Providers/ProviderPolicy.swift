import Foundation

enum ProviderCachePolicy: Sendable {
  case allowed(TimeInterval)
  case prohibited
}

enum ProviderPolicy {
  static func cachePolicy(for provider: ProviderID) -> ProviderCachePolicy {
    switch provider {
    case .nationalArchives: .prohibited
    case .pixabay: .allowed(86_400)
    default: .allowed(1_800)
    }
  }

  static func apiKeyHelpURL(for provider: ProviderID) -> URL? {
    let value: String? =
      switch provider {
      case .pexels: "https://www.pexels.com/api/"
      case .pixabay: "https://pixabay.com/api/docs/"
      case .youtube: "https://console.cloud.google.com/apis/library/youtube.googleapis.com"
      case .nationalArchives: "https://catalog.archives.gov/api-keys/register"
      case .europeana: "https://pro.europeana.eu/page/get-api"
      case .coverr: "https://coverr.co/developers"
      case .vimeo: "https://developer.vimeo.com/apps"
      case .videvo: "https://www.videvo.net/api/"
      default: nil
      }
    return URLValidator.remote(value)
  }

  static func officialSearchURL(for provider: ProviderID, query: String) -> URL? {
    let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let value: String? =
      switch provider {
      case .nasa: "https://images.nasa.gov/search?q=\(escaped)"
      case .libraryOfCongress: "https://www.loc.gov/film-and-videos/?q=\(escaped)"
      case .nationalArchives: "https://catalog.archives.gov/search?q=\(escaped)"
      case .europeana: "https://www.europeana.eu/en/search?query=\(escaped)"
      case .peertube: "https://sepiasearch.org/search?search=\(escaped)"
      case .videvo: "https://www.videvo.net/stock-video-footage/\(escaped)/"
      case .videezy: "https://www.videezy.com/free-video/\(escaped)"
      case .mixkit: "https://mixkit.co/free-stock-video/?q=\(escaped)"
      case .coverr: "https://coverr.co/stock-video-footage?query=\(escaped)"
      case .vimeo: "https://vimeo.com/search?q=\(escaped)"
      default: nil
      }
    return URLValidator.remote(value)
  }

  static let nationalArchivesNotice =
    "This product uses the National Archives Catalog API but is not endorsed or certified by the National Archives and Records Administration."
}

struct LimitedDiscoveryProvider: MediaProvider {
  let info: ProviderInfo

  init(id: ProviderID) {
    info = ProviderInfo(
      id: id, displayName: id.displayName, mode: .limited, requiresAPIKey: false,
      capabilities: ProviderCapabilities(
        search: .bestEffort, preview: .unavailable, metadata: .unavailable,
        license: .unavailable, download: .unavailable, supportsVideo: true,
        supportsImage: id == .europeana, supportsAudio: id == .europeana,
        accessMethods: [.publicInterface]))
  }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    guard let url = ProviderPolicy.officialSearchURL(for: info.id, query: request.query) else {
      throw ProviderError.unsupported
    }
    throw ProviderError.limitedMode(info.id, url)
  }

  func testConnection() async throws {
    throw ProviderError.limitedMode(
      info.id, ProviderPolicy.officialSearchURL(for: info.id, query: "history")!)
  }
}

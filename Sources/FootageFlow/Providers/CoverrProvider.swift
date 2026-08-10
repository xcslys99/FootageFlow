import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct CoverrProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .coverr, displayName: "Coverr", mode: .officialAPI, requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .supported,
      download: .supported, supportsVideo: true, supportsImage: false,
      pagination: .supported, accessMethods: [.officialAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.missingAPIKey(.coverr)
    }
    guard request.mediaType == .video || request.mediaType == .all else {
      return ProviderPage(assets: [], continuation: nil)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .coverr, minimumInterval: .milliseconds(350))
    let page = max(0, continuation?.page ?? 0)
    let pageSize = max(1, min(request.pageSize, 40))
    let url = try URL.endpoint(
      "https://api.coverr.co/videos",
      queryItems: [
        URLQueryItem(name: "query", value: request.query),
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "page_size", value: String(pageSize)),
        URLQueryItem(name: "urls", value: "true"),
      ])
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let response = try await HTTPClient.shared.decode(
      CoverrSearchResponse.self, request: urlRequest, maxRetries: 1)
    let assets = response.hits.enumerated().compactMap { index, item in
      Self.asset(item, query: request.query, index: index)
    }
    let hasMore = page + 1 < response.pages && !response.hits.isEmpty
    return ProviderPage(
      assets: assets,
      continuation: hasMore ? ProviderContinuation(page: page + 1) : nil,
      totalResults: response.total)
  }

  static func asset(_ item: CoverrVideo, query: String, index: Int) -> MediaAsset? {
    guard let source = URLValidator.remote("https://coverr.co/videos/\(item.id)") else {
      return nil
    }
    let preview = URLValidator.remote(item.urls?.mp4Preview ?? item.urls?.mp4)
    let download = URLValidator.remote(item.urls?.mp4Download ?? item.urls?.mp4)
    let rights = RightsInfo(
      statement: "Coverr API License", uri: URLValidator.remote("https://coverr.co/license/"),
      source: "Coverr API and license page", known: true, openLicense: true,
      attributionRequired: true, commercialUseKnown: true)
    return MediaAsset(
      id: item.id, provider: .coverr, title: item.title,
      description: item.description, thumbnailURL: URLValidator.remote(item.thumbnail),
      previewURL: preview, downloadURL: download, sourcePageURL: source, creator: nil,
      license: "Coverr API License — attribution required",
      licenseURL: URLValidator.remote("https://coverr.co/license/"),
      licenseStatus: .attributionRequired, width: item.maxWidth, height: item.maxHeight,
      duration: item.duration, fileType: "video/mp4", mediaType: .video,
      publishedDate: ProviderUtilities.parseDate(item.publishedAt), downloadable: download != nil,
      originalMetadata: [
        "tags": item.tags.joined(separator: ", "), "aspectRatio": item.aspectRatio ?? "",
      ], searchKeyword: query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: download == nil ? .unavailable : .direct)
  }
}

struct CoverrSearchResponse: Decodable {
  let page, pages, pageSize, total: Int
  let hits: [CoverrVideo]
  enum CodingKeys: String, CodingKey {
    case page, pages, total, hits
    case pageSize = "page_size"
  }
}

struct CoverrVideo: Decodable {
  let id, title: String
  let description, thumbnail, publishedAt, aspectRatio: String?
  let tags: [String]
  let duration: Double?
  let maxHeight, maxWidth: Int?
  let urls: CoverrURLs?
  enum CodingKeys: String, CodingKey {
    case id, title, description, thumbnail, tags, duration, urls
    case publishedAt = "published_at"
    case aspectRatio = "aspect_ratio"
    case maxHeight = "max_height"
    case maxWidth = "max_width"
  }
}

struct CoverrURLs: Decodable {
  let mp4, mp4Preview, mp4Download: String?
  enum CodingKeys: String, CodingKey {
    case mp4
    case mp4Preview = "mp4_preview"
    case mp4Download = "mp4_download"
  }
}

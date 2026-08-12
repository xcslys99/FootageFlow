import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Dailymotion is intentionally discovery-only. This uses Dailymotion's documented public
/// client endpoint and never marks a video downloadable or reusable without explicit rights data.
struct DailymotionProvider: MediaProvider {
  let info = ProviderInfo(
    id: .dailymotion, displayName: "Dailymotion", mode: .publicAPI, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .bestEffort, metadata: .supported, license: .unavailable,
      download: .unavailable, supportsVideo: true, supportsImage: false,
      pagination: .supported, accessMethods: [.officialAPI, .publicAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard request.mediaType == .all || request.mediaType == .video else {
      return ProviderPage(assets: [], continuation: nil, totalResults: 0)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .dailymotion, minimumInterval: .milliseconds(350))
    let page = max(1, continuation?.page ?? 1)
    let limit = max(1, min(request.pageSize, 40))
    let fields = [
      "id", "title", "description", "duration", "thumbnail_720_url", "url",
      "owner.screenname", "created_time",
    ].joined(separator: ",")
    let url = try URL.endpoint(
      "https://api.dailymotion.com/videos",
      queryItems: [
        URLQueryItem(name: "search", value: request.query),
        URLQueryItem(name: "sort", value: "relevance"),
        URLQueryItem(name: "limit", value: String(limit)),
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "fields", value: fields),
      ])
    let response = try await HTTPClient.shared.decode(
      DailymotionSearchResponse.self, request: URLRequest(url: url), maxRetries: 1)
    let assets = response.list.enumerated().compactMap { index, item in
      Self.asset(item, query: request.query, index: index)
    }
    return ProviderPage(
      assets: assets,
      continuation: response.hasMore && !assets.isEmpty ? .nextPage(page + 1) : nil,
      totalResults: response.total)
  }

  static func asset(_ item: DailymotionVideo, query: String, index: Int) -> MediaAsset? {
    guard let source = ProviderUtilities.safeURL(item.url) else { return nil }
    let thumbnails = ThumbnailResolver.candidates(
      provider: .dailymotion, rawValues: [item.thumbnail720URL], originalPageURL: source)
    let date = item.createdTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    return MediaAsset(
      id: item.id, provider: .dailymotion, title: item.title,
      description: ProviderUtilities.cleanHTML(item.description), thumbnailURL: thumbnails.first,
      previewURL: nil, downloadURL: nil, sourcePageURL: source,
      creator: item.ownerScreenname?.nilIfEmpty, license: nil, licenseURL: nil,
      licenseStatus: .unknown, width: nil, height: nil, duration: item.duration,
      fileType: "Dailymotion", mediaType: .video, publishedDate: date,
      downloadable: false,
      originalMetadata: [
        "sourceName": "Dailymotion", "discoveryOnly": "true",
        "rightsNotice": tr("attribution.rightsUnknown"),
      ], searchKeyword: query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: RightsInfo(
        statement: nil, source: "Dailymotion public metadata", known: false),
      downloadAvailability: .unavailable, thumbnailCandidates: thumbnails)
  }
}

struct DailymotionSearchResponse: Decodable {
  let page, limit, total: Int
  let hasMore: Bool
  let list: [DailymotionVideo]

  enum CodingKeys: String, CodingKey {
    case page, limit, total, list
    case hasMore = "has_more"
  }
}

struct DailymotionVideo: Decodable {
  let id, title: String
  let description, thumbnail720URL, url, ownerScreenname: String?
  let duration: Double?
  let createdTime: Int?

  enum CodingKeys: String, CodingKey {
    case id, title, description, duration, url
    case thumbnail720URL = "thumbnail_720_url"
    case ownerScreenname = "owner.screenname"
    case createdTime = "created_time"
  }
}

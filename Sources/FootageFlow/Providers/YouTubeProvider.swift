import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct YouTubeProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .youtube, displayName: "YouTube", mode: .officialAPI, requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .bestEffort, metadata: .supported, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: false,
      pagination: .supported,
      accessMethods: [.officialAPI, .externalTool]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.youtube) }
    guard request.mediaType != .image && request.mediaType != .audio else {
      return ProviderPage(assets: [], continuation: nil)
    }
    var items = [
      URLQueryItem(name: "part", value: "snippet"),
      URLQueryItem(name: "type", value: "video"),
      URLQueryItem(name: "q", value: request.query),
      URLQueryItem(name: "maxResults", value: String(min(request.pageSize, 50))),
      URLQueryItem(name: "safeSearch", value: "moderate"),
      URLQueryItem(name: "key", value: apiKey),
    ]
    if let token = continuation?.token {
      items.append(URLQueryItem(name: "pageToken", value: token))
    }
    let url = try URL.endpoint(
      "https://www.googleapis.com/youtube/v3/search", queryItems: items)
    let response = try await HTTPClient.shared.decode(
      YouTubeSearchResponse.self, request: URLRequest(url: url), maxRetries: 1)
    let assets: [MediaAsset] = response.items.enumerated().compactMap { index, item in
      guard let videoID = item.id.videoId,
        let page = URLValidator.remote("https://www.youtube.com/watch?v=\(videoID)")
      else { return nil }
      let thumb =
        item.snippet.thumbnails.high ?? item.snippet.thumbnails.medium
        ?? item.snippet.thumbnails.defaultValue
      let thumbnails = ThumbnailResolver.candidates(
        provider: .youtube,
        rawValues: [
          item.snippet.thumbnails.high?.url, item.snippet.thumbnails.medium?.url,
          item.snippet.thumbnails.defaultValue?.url,
          "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg",
          "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg",
        ], originalPageURL: page)
      return MediaAsset(
        id: videoID, provider: .youtube, title: item.snippet.title,
        description: item.snippet.description, thumbnailURL: thumbnails.first,
        previewURL: nil, downloadURL: page, sourcePageURL: page, creator: item.snippet.channelTitle,
        license: nil, licenseURL: nil, licenseStatus: .unknown, width: thumb?.width,
        height: thumb?.height, duration: nil, fileType: "YouTube", mediaType: .video,
        publishedDate: ProviderUtilities.parseDate(item.snippet.publishedAt), downloadable: true,
        originalMetadata: ["channelID": item.snippet.channelId], searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.01, downloadStrategy: .ytDLP,
        downloadAvailability: .conditional, thumbnailCandidates: thumbnails)
    }
    return ProviderPage(
      assets: assets,
      continuation: response.nextPageToken.map { ProviderContinuation(token: $0) },
      totalResults: response.pageInfo?.totalResults)
  }
}

struct YouTubeSearchResponse: Decodable {
  let items: [YouTubeItem]
  let nextPageToken: String?
  let pageInfo: YouTubePageInfo?
}
struct YouTubePageInfo: Decodable { let totalResults, resultsPerPage: Int? }
struct YouTubeItem: Decodable {
  let id: YouTubeID
  let snippet: YouTubeSnippet
}
struct YouTubeID: Decodable { let videoId: String? }
struct YouTubeSnippet: Decodable {
  let publishedAt, channelId, title, description, channelTitle: String
  let thumbnails: YouTubeThumbnails
}
struct YouTubeThumbnails: Decodable {
  let `default`, medium, high: YouTubeThumbnail?
  var defaultValue: YouTubeThumbnail? { self.default }
}
struct YouTubeThumbnail: Decodable {
  let url: String
  let width, height: Int?
}

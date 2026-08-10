import Foundation

struct YouTubeYTDLPProvider: MediaProvider {
  let service: YTDLPService
  let info = ProviderInfo(
    id: .youtube, displayName: "YouTube", mode: .ytDLP, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .bestEffort, preview: .bestEffort, metadata: .bestEffort,
      license: .bestEffort, download: .bestEffort, supportsVideo: true,
      supportsImage: false, accessMethods: [.externalTool]))

  init(service: YTDLPService = YTDLPService()) { self.service = service }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    guard request.mediaType != .image else { return [] }
    let values = try await service.search(query: request.query, limit: min(request.pageSize, 12))
    return Self.assets(from: values, query: request.query)
  }

  static func assets(from values: [YTDLPSearchItem], query: String) -> [MediaAsset] {
    return values.enumerated().compactMap { index, item in
      // Flat-playlist results commonly expose `url` as a bare video ID. Prefer an actual
      // webpage URL and always keep the canonical watch-page fallback.
      let source =
        URLValidator.remote(item.webpageURL) ?? URLValidator.remote(item.url)
        ?? URLValidator.remote("https://www.youtube.com/watch?v=\(item.id)")
      guard let source else { return nil }
      let thumbnail = item.thumbnails?.max {
        ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0)
      }
      let thumbnailURL =
        URLValidator.remote(thumbnail?.url)
        ?? URLValidator.remote("https://i.ytimg.com/vi/\(item.id)/hqdefault.jpg")
      return MediaAsset(
        id: item.id, provider: .youtube, title: item.title ?? "YouTube \(item.id)",
        description: nil, thumbnailURL: thumbnailURL, previewURL: nil,
        downloadURL: source, sourcePageURL: source, creator: item.channel ?? item.uploader,
        license: nil, licenseURL: nil, licenseStatus: .unknown, width: thumbnail?.width,
        height: thumbnail?.height, duration: item.duration, fileType: "video",
        mediaType: .video, publishedDate: nil, downloadable: true,
        originalMetadata: ["accessMode": ProviderMode.ytDLP.rawValue],
        searchKeyword: query, relevanceScore: 0.9 - Double(index) * 0.01,
        downloadStrategy: .ytDLP)
    }
  }

  static func assets(fromJSON data: Data, query: String) throws -> [MediaAsset] {
    do {
      let response = try JSONDecoder().decode(YTDLPSearchResponse.self, from: data)
      return assets(from: response.entries, query: query)
    } catch {
      throw ProviderError.invalidResponse
    }
  }
}

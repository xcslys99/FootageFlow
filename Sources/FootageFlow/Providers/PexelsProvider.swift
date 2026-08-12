import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct PexelsProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .pexels, displayName: "Pexels", mode: .officialAPI, requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .supported,
      download: .supported, supportsVideo: true, supportsImage: true,
      pagination: .supported,
      accessMethods: [.officialAPI, .directSearch]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.pexels) }
    guard request.mediaType != .audio else { return ProviderPage(assets: [], continuation: nil) }
    let page = max(1, continuation?.page ?? 1)
    var results: [MediaAsset] = []
    var hasMore = false
    var totalResults = 0
    if request.mediaType != .image {
      let value = try await searchVideos(request, page: page)
      results += value.assets
      hasMore = hasMore || value.hasMore
      totalResults += value.totalResults
    }
    if request.mediaType != .video {
      let value = try await searchPhotos(request, page: page)
      results += value.assets
      hasMore = hasMore || value.hasMore
      totalResults += value.totalResults
    }
    return ProviderPage(
      assets: results,
      continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: totalResults)
  }

  private func authorizedRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "Authorization")
    return request
  }

  private func commonItems(_ request: SearchRequest, page: Int) -> [URLQueryItem] {
    var items = [
      URLQueryItem(name: "query", value: request.query),
      URLQueryItem(name: "per_page", value: String(min(request.pageSize, 40))),
      URLQueryItem(name: "page", value: String(page)),
    ]
    if [.landscape, .portrait, .square].contains(request.orientation) {
      items.append(URLQueryItem(name: "orientation", value: request.orientation.rawValue))
    }
    return items
  }

  private func searchVideos(_ request: SearchRequest, page: Int) async throws
    -> (assets: [MediaAsset], hasMore: Bool, totalResults: Int)
  {
    var items = commonItems(request, page: page)
    if let height = request.resolution.minimumHeight {
      let size = height >= 2160 ? "large" : (height >= 1080 ? "medium" : "small")
      items.append(URLQueryItem(name: "size", value: size))
    }
    let url = try URL.endpoint("https://api.pexels.com/v1/videos/search", queryItems: items)
    let response = try await HTTPClient.shared.decode(
      PexelsVideoResponse.self, request: authorizedRequest(url: url))
    let assets = response.videos.enumerated().compactMap { index, video -> MediaAsset? in
      guard let source = URLValidator.remote(video.url) else { return nil }
      let valid = video.videoFiles.filter {
        $0.fileType?.contains("video") == true && $0.link.hasPrefix("http")
      }
      let best = valid.max {
        ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0)
      }
      let preview = valid.min {
        ($0.width ?? 99999) * ($0.height ?? 99999) < ($1.width ?? 99999) * ($1.height ?? 99999)
      }
      let download = URLValidator.remote(best?.link)
      let thumbnails = ThumbnailResolver.candidates(
        provider: .pexels, rawValues: [video.image], originalPageURL: source)
      return MediaAsset(
        id: String(video.id), provider: .pexels, title: "\(request.query) · Pexels \(video.id)",
        description: nil, thumbnailURL: thumbnails.first,
        previewURL: URLValidator.remote(preview?.link ?? best?.link), downloadURL: download,
        sourcePageURL: source, creator: video.user.name, license: "Pexels License",
        licenseURL: URLValidator.remote("https://www.pexels.com/license/"), licenseStatus: .safe,
        width: best?.width ?? video.width, height: best?.height ?? video.height,
        duration: Double(video.duration), fileType: best?.fileType ?? "video/mp4",
        mediaType: .video, publishedDate: nil, downloadable: download != nil,
        originalMetadata: ["userURL": video.user.url, "syntheticTitle": "true"],
        searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.01, thumbnailCandidates: thumbnails)
    }
    return (assets, response.nextPage != nil, response.totalResults ?? assets.count)
  }

  private func searchPhotos(_ request: SearchRequest, page: Int) async throws
    -> (assets: [MediaAsset], hasMore: Bool, totalResults: Int)
  {
    let url = try URL.endpoint(
      "https://api.pexels.com/v1/search", queryItems: commonItems(request, page: page))
    let response = try await HTTPClient.shared.decode(
      PexelsPhotoResponse.self, request: authorizedRequest(url: url))
    let assets: [MediaAsset] = response.photos.enumerated().compactMap { index, photo in
      guard let source = URLValidator.remote(photo.url),
        let download = URLValidator.remote(photo.src.original)
      else { return nil }
      let thumbnails = ThumbnailResolver.candidates(
        provider: .pexels, rawValues: [photo.src.medium, photo.src.large, photo.src.original],
        originalPageURL: source)
      return MediaAsset(
        id: String(photo.id), provider: .pexels,
        title: photo.alt?.isEmpty == false ? photo.alt! : "Pexels Photo \(photo.id)",
        description: photo.alt, thumbnailURL: thumbnails.first,
        previewURL: URLValidator.remote(photo.src.large), downloadURL: download,
        sourcePageURL: source, creator: photo.photographer, license: "Pexels License",
        licenseURL: URLValidator.remote("https://www.pexels.com/license/"), licenseStatus: .safe,
        width: photo.width, height: photo.height, duration: nil, fileType: "image/jpeg",
        mediaType: .image, publishedDate: nil, downloadable: true,
        originalMetadata: ["photographerURL": photo.photographerURL], searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.01, thumbnailCandidates: thumbnails)
    }
    return (assets, response.nextPage != nil, response.totalResults ?? assets.count)
  }
}

struct PexelsVideoResponse: Decodable {
  let videos: [PexelsVideo]
  let totalResults: Int?
  let nextPage: String?
  enum CodingKeys: String, CodingKey {
    case videos
    case totalResults = "total_results"
    case nextPage = "next_page"
  }
}
struct PexelsVideo: Decodable {
  let id, width, height, duration: Int
  let url, image: String
  let user: PexelsUser
  let videoFiles: [PexelsVideoFile]
  enum CodingKeys: String, CodingKey {
    case id, width, height, duration, url, image, user
    case videoFiles = "video_files"
  }
}
struct PexelsUser: Decodable { let name, url: String }
struct PexelsVideoFile: Decodable {
  let width, height: Int?
  let link: String
  let fileType: String?
  enum CodingKeys: String, CodingKey {
    case width, height, link
    case fileType = "file_type"
  }
}
struct PexelsPhotoResponse: Decodable {
  let photos: [PexelsPhoto]
  let totalResults: Int?
  let nextPage: String?
  enum CodingKeys: String, CodingKey {
    case photos
    case totalResults = "total_results"
    case nextPage = "next_page"
  }
}
struct PexelsPhoto: Decodable {
  let id, width, height: Int
  let url, photographer: String
  let photographerURL: String
  let alt: String?
  let src: PexelsPhotoSource
  enum CodingKeys: String, CodingKey {
    case id, width, height, url, photographer, alt, src
    case photographerURL = "photographer_url"
  }
}
struct PexelsPhotoSource: Decodable { let original, large, medium: String }

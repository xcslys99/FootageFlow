import Foundation

struct PixabayProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .pixabay, displayName: "Pixabay", requiresAPIKey: true, supportsVideo: true,
    supportsImage: true, supportsDownload: true)

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.pixabay) }
    var results: [MediaAsset] = []
    if request.mediaType != .image { results += try await videos(request) }
    if request.mediaType != .video { results += try await images(request) }
    return results
  }

  private func baseItems(_ request: SearchRequest) -> [URLQueryItem] {
    var items = [
      URLQueryItem(name: "key", value: apiKey),
      URLQueryItem(name: "q", value: String(request.query.prefix(100))),
      URLQueryItem(name: "per_page", value: String(max(3, min(request.pageSize, 50)))),
      URLQueryItem(name: "safesearch", value: "true"),
    ]
    if request.orientation == .landscape {
      items.append(URLQueryItem(name: "orientation", value: "horizontal"))
    }
    if request.orientation == .portrait {
      items.append(URLQueryItem(name: "orientation", value: "vertical"))
    }
    if let height = request.resolution.minimumHeight {
      items.append(URLQueryItem(name: "min_height", value: String(height)))
    }
    return items
  }

  private func videos(_ request: SearchRequest) async throws -> [MediaAsset] {
    let url = try URL.endpoint("https://pixabay.com/api/videos/", queryItems: baseItems(request))
    let response = try await HTTPClient.shared.decode(
      PixabayVideoResponse.self, request: URLRequest(url: url))
    return response.hits.enumerated().compactMap { index, hit in
      let files = [hit.videos.large, hit.videos.medium, hit.videos.small, hit.videos.tiny]
        .compactMap { $0 }.filter { !$0.url.isEmpty }
      guard let best = files.max(by: { $0.width * $0.height < $1.width * $1.height }),
        let page = URLValidator.remote(hit.pageURL), let download = URLValidator.remote(best.url)
      else { return nil }
      let preview = files.min(by: { $0.width * $0.height < $1.width * $1.height }) ?? best
      return MediaAsset(
        id: String(hit.id), provider: .pixabay, title: hit.tags ?? "Pixabay Video \(hit.id)",
        description: hit.tags, thumbnailURL: URLValidator.remote(preview.thumbnail),
        previewURL: URLValidator.remote(preview.url), downloadURL: download, sourcePageURL: page,
        creator: hit.user, license: "Pixabay Content License",
        licenseURL: URLValidator.remote("https://pixabay.com/service/license-summary/"),
        licenseStatus: .safe, width: best.width, height: best.height,
        duration: hit.duration.map(Double.init), fileType: "video/mp4", mediaType: .video,
        publishedDate: nil, downloadable: true, originalMetadata: [:], searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.01)
    }
  }

  private func images(_ request: SearchRequest) async throws -> [MediaAsset] {
    let url = try URL.endpoint(
      "https://pixabay.com/api/",
      queryItems: baseItems(request) + [URLQueryItem(name: "image_type", value: "all")])
    let response = try await HTTPClient.shared.decode(
      PixabayImageResponse.self, request: URLRequest(url: url))
    return response.hits.enumerated().compactMap { index, hit in
      guard let page = URLValidator.remote(hit.pageURL) else { return nil }
      let download = hit.imageURL ?? hit.fullHDURL ?? hit.largeImageURL
      guard let downloadURL = URLValidator.remote(download) else { return nil }
      return MediaAsset(
        id: String(hit.id), provider: .pixabay, title: hit.tags ?? "Pixabay Image \(hit.id)",
        description: hit.tags, thumbnailURL: URLValidator.remote(hit.webformatURL),
        previewURL: URLValidator.remote(hit.largeImageURL), downloadURL: downloadURL,
        sourcePageURL: page, creator: hit.user, license: "Pixabay Content License",
        licenseURL: URLValidator.remote("https://pixabay.com/service/license-summary/"),
        licenseStatus: .safe, width: hit.imageWidth, height: hit.imageHeight, duration: nil,
        fileType: "image/jpeg", mediaType: .image, publishedDate: nil, downloadable: true,
        originalMetadata: [:], searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.01)
    }
  }
}

struct PixabayVideoResponse: Decodable { let hits: [PixabayVideoHit] }
struct PixabayVideoHit: Decodable {
  let id: Int
  let pageURL: String
  let tags: String?
  let duration: Int?
  let user: String?
  let videos: PixabayVideos
}
struct PixabayVideos: Decodable { let large, medium, small, tiny: PixabayVideoFile? }
struct PixabayVideoFile: Decodable {
  let url: String
  let width, height: Int
  let size: Int?
  let thumbnail: String?
}
struct PixabayImageResponse: Decodable { let hits: [PixabayImageHit] }
struct PixabayImageHit: Decodable {
  let id: Int
  let pageURL: String
  let tags: String?
  let webformatURL, largeImageURL: String
  let fullHDURL, imageURL: String?
  let imageWidth, imageHeight: Int
  let user: String?
}

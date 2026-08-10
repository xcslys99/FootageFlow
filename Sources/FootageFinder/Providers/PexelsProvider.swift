import Foundation

struct PexelsProvider: MediaProvider {
    let apiKey: String
    let info = ProviderInfo(id: .pexels, displayName: "Pexels", requiresAPIKey: true, supportsVideo: true, supportsImage: true, supportsDownload: true)

    func search(_ request: SearchRequest) async throws -> [MediaAsset] {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.pexels) }
        var results: [MediaAsset] = []
        if request.mediaType != .image { results += try await searchVideos(request) }
        if request.mediaType != .video { results += try await searchPhotos(request) }
        return results
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        return request
    }

    private func commonItems(_ request: SearchRequest) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "query", value: request.query), URLQueryItem(name: "per_page", value: String(min(request.pageSize, 40)))]
        if [.landscape, .portrait, .square].contains(request.orientation) { items.append(URLQueryItem(name: "orientation", value: request.orientation.rawValue)) }
        return items
    }

    private func searchVideos(_ request: SearchRequest) async throws -> [MediaAsset] {
        var items = commonItems(request)
        if let height = request.resolution.minimumHeight {
            let size = height >= 2160 ? "large" : (height >= 1080 ? "medium" : "small")
            items.append(URLQueryItem(name: "size", value: size))
        }
        let url = try URL.endpoint("https://api.pexels.com/v1/videos/search", queryItems: items)
        let response = try await HTTPClient.shared.decode(PexelsVideoResponse.self, request: authorizedRequest(url: url))
        return response.videos.enumerated().compactMap { index, video -> MediaAsset? in
            guard let source = URL(string: video.url) else { return nil }
            let valid = video.videoFiles.filter { $0.fileType?.contains("video") == true && $0.link.hasPrefix("http") }
            let best = valid.max { ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0) }
            let preview = valid.min { ($0.width ?? 99999) * ($0.height ?? 99999) < ($1.width ?? 99999) * ($1.height ?? 99999) }
            return MediaAsset(id: String(video.id), provider: .pexels, title: "\(request.query) · Pexels \(video.id)", description: nil, thumbnailURL: URL(string: video.image), previewURL: URL(string: preview?.link ?? best?.link ?? ""), downloadURL: URL(string: best?.link ?? ""), sourcePageURL: source, creator: video.user.name, license: "Pexels License", licenseURL: URL(string: "https://www.pexels.com/license/"), licenseStatus: .safe, width: best?.width ?? video.width, height: best?.height ?? video.height, duration: Double(video.duration), fileType: best?.fileType ?? "video/mp4", mediaType: .video, publishedDate: nil, downloadable: best != nil, originalMetadata: ["userURL": video.user.url], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01)
        }
    }

    private func searchPhotos(_ request: SearchRequest) async throws -> [MediaAsset] {
        let url = try URL.endpoint("https://api.pexels.com/v1/search", queryItems: commonItems(request))
        let response = try await HTTPClient.shared.decode(PexelsPhotoResponse.self, request: authorizedRequest(url: url))
        return response.photos.enumerated().compactMap { index, photo in
            guard let source = URL(string: photo.url) else { return nil }
            return MediaAsset(id: String(photo.id), provider: .pexels, title: photo.alt?.isEmpty == false ? photo.alt! : "Pexels Photo \(photo.id)", description: photo.alt, thumbnailURL: URL(string: photo.src.medium), previewURL: URL(string: photo.src.large), downloadURL: URL(string: photo.src.original), sourcePageURL: source, creator: photo.photographer, license: "Pexels License", licenseURL: URL(string: "https://www.pexels.com/license/"), licenseStatus: .safe, width: photo.width, height: photo.height, duration: nil, fileType: "image/jpeg", mediaType: .image, publishedDate: nil, downloadable: true, originalMetadata: ["photographerURL": photo.photographerURL], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01)
        }
    }
}

struct PexelsVideoResponse: Decodable { let videos: [PexelsVideo] }
struct PexelsVideo: Decodable {
    let id, width, height, duration: Int
    let url, image: String
    let user: PexelsUser
    let videoFiles: [PexelsVideoFile]
    enum CodingKeys: String, CodingKey { case id, width, height, duration, url, image, user; case videoFiles = "video_files" }
}
struct PexelsUser: Decodable { let name, url: String }
struct PexelsVideoFile: Decodable {
    let width, height: Int?
    let link: String
    let fileType: String?
    enum CodingKeys: String, CodingKey { case width, height, link; case fileType = "file_type" }
}
struct PexelsPhotoResponse: Decodable { let photos: [PexelsPhoto] }
struct PexelsPhoto: Decodable {
    let id, width, height: Int
    let url, photographer: String
    let photographerURL: String
    let alt: String?
    let src: PexelsPhotoSource
    enum CodingKeys: String, CodingKey { case id, width, height, url, photographer, alt, src; case photographerURL = "photographer_url" }
}
struct PexelsPhotoSource: Decodable { let original, large, medium: String }

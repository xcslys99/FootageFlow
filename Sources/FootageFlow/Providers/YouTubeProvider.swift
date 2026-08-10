import Foundation

struct YouTubeProvider: MediaProvider {
    let apiKey: String
    let info = ProviderInfo(id: .youtube, displayName: "YouTube", requiresAPIKey: true, supportsVideo: true, supportsImage: false, supportsDownload: false)

    func search(_ request: SearchRequest) async throws -> [MediaAsset] {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.youtube) }
        guard request.mediaType != .image else { return [] }
        let url = try URL.endpoint("https://www.googleapis.com/youtube/v3/search", queryItems: [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "q", value: request.query),
            URLQueryItem(name: "maxResults", value: String(min(request.pageSize, 25))),
            URLQueryItem(name: "safeSearch", value: "moderate"),
            URLQueryItem(name: "key", value: apiKey)
        ])
        let response = try await HTTPClient.shared.decode(YouTubeSearchResponse.self, request: URLRequest(url: url), maxRetries: 1)
        return response.items.enumerated().compactMap { index, item in
            guard let videoID = item.id.videoId, let page = URLValidator.remote("https://www.youtube.com/watch?v=\(videoID)") else { return nil }
            let thumb = item.snippet.thumbnails.high ?? item.snippet.thumbnails.medium ?? item.snippet.thumbnails.defaultValue
            return MediaAsset(id: videoID, provider: .youtube, title: item.snippet.title, description: item.snippet.description, thumbnailURL: URLValidator.remote(thumb?.url), previewURL: nil, downloadURL: nil, sourcePageURL: page, creator: item.snippet.channelTitle, license: nil, licenseURL: nil, licenseStatus: .unknown, width: thumb?.width, height: thumb?.height, duration: nil, fileType: "YouTube", mediaType: .video, publishedDate: ProviderUtilities.parseDate(item.snippet.publishedAt), downloadable: false, originalMetadata: ["channelID": item.snippet.channelId], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01)
        }
    }
}

struct YouTubeSearchResponse: Decodable { let items: [YouTubeItem] }
struct YouTubeItem: Decodable { let id: YouTubeID; let snippet: YouTubeSnippet }
struct YouTubeID: Decodable { let videoId: String? }
struct YouTubeSnippet: Decodable {
    let publishedAt, channelId, title, description, channelTitle: String
    let thumbnails: YouTubeThumbnails
}
struct YouTubeThumbnails: Decodable {
    let `default`, medium, high: YouTubeThumbnail?
    var defaultValue: YouTubeThumbnail? { self.default }
}
struct YouTubeThumbnail: Decodable { let url: String; let width, height: Int? }

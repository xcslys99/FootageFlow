import Foundation

struct WikimediaProvider: MediaProvider {
    let info = ProviderInfo(id: .wikimedia, displayName: "Wikimedia Commons", requiresAPIKey: false, supportsVideo: true, supportsImage: true, supportsDownload: true)

    func search(_ request: SearchRequest) async throws -> [MediaAsset] {
        let effectiveQuery = request.mediaType == .video && !request.query.contains("filetype:") ? "\(request.query) filetype:video" : request.query
        let items = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: effectiveQuery),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: String(min(request.pageSize, 24))),
            URLQueryItem(name: "gsrwhat", value: "text"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|size|mime|mediatype|extmetadata|timestamp|user"),
            URLQueryItem(name: "iiurlwidth", value: "640"),
            URLQueryItem(name: "iiextmetadatalanguage", value: "zh"),
            URLQueryItem(name: "iiextmetadatafilter", value: "ImageDescription|ObjectName|Artist|Credit|LicenseShortName|LicenseUrl|UsageTerms|DateTimeOriginal")
        ]
        let url = try URL.endpoint("https://commons.wikimedia.org/w/api.php", queryItems: items)
        let response = try await HTTPClient.shared.decode(WikimediaResponse.self, request: URLRequest(url: url))
        return (response.query?.pages ?? []).enumerated().compactMap { index, page in
            guard let image = page.imageinfo?.first, let original = URLValidator.remote(image.url), let source = URLValidator.remote(image.descriptionurl) else { return nil }
            let mime = image.mime ?? ""
            let type: MediaType
            if mime.hasPrefix("video/") || mime == "application/ogg" { type = .video }
            else if mime.hasPrefix("image/") { type = .image }
            else { return nil }
            if request.mediaType != .all && request.mediaType != type { return nil }
            let metadata = image.extmetadata ?? [:]
            let rawLicenseName = metadata["LicenseShortName"]?.value ?? metadata["UsageTerms"]?.value
            let licenseURLText = metadata["LicenseUrl"]?.value
            let licenseName = ProviderUtilities.licenseName(name: rawLicenseName, url: licenseURLText)
            let creator = ProviderUtilities.cleanHTML(metadata["Artist"]?.value) ?? image.user
            let title = ProviderUtilities.cleanHTML(metadata["ObjectName"]?.value) ?? page.title.replacingOccurrences(of: "File:", with: "")
            let description = ProviderUtilities.cleanHTML(metadata["ImageDescription"]?.value)
            let thumbnail = URLValidator.remote(image.thumburl ?? image.url)
            let playablePreview = type == .video && ["mp4", "m4v", "mov"].contains(original.pathExtension.lowercased()) ? original : (type == .image ? thumbnail : nil)
            return MediaAsset(id: String(page.pageid), provider: .wikimedia, title: title, description: description, thumbnailURL: thumbnail, previewURL: playablePreview, downloadURL: original, sourcePageURL: source, creator: creator, license: licenseName, licenseURL: URLValidator.remote(licenseURLText), licenseStatus: ProviderUtilities.licenseStatus(name: licenseName, url: licenseURLText), width: image.width, height: image.height, duration: nil, fileType: mime.isEmpty ? original.pathExtension : mime, mediaType: type, publishedDate: ProviderUtilities.parseDate(metadata["DateTimeOriginal"]?.value ?? image.timestamp), downloadable: true, originalMetadata: ["credit": ProviderUtilities.cleanHTML(metadata["Credit"]?.value) ?? "", "uploader": image.user ?? ""], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01)
        }
    }
}

struct WikimediaResponse: Decodable { let query: WikimediaQuery? }
struct WikimediaQuery: Decodable { let pages: [WikimediaPage] }
struct WikimediaPage: Decodable { let pageid: Int; let title: String; let imageinfo: [WikimediaImageInfo]? }
struct WikimediaImageInfo: Decodable {
    let url: String; let descriptionurl, thumburl, mime, mediatype, timestamp, user: String?
    let width, height: Int?; let extmetadata: [String: WikimediaMetadataValue]?
}
struct WikimediaMetadataValue: Decodable { let value: String }

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Vimeo is intentionally discovery-only. Public metadata never implies reuse or download rights.
struct VimeoProvider: MediaProvider {
  let accessToken: String
  let info = ProviderInfo(
    id: .vimeo, displayName: "Vimeo", mode: .officialAPI, requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .bestEffort, metadata: .supported, license: .bestEffort,
      download: .unavailable, supportsVideo: true, supportsImage: false,
      pagination: .supported, accessMethods: [.officialAPI, .publicInterface]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.missingAPIKey(.vimeo)
    }
    guard request.mediaType == .video || request.mediaType == .all else {
      return ProviderPage(assets: [], continuation: nil)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .vimeo, minimumInterval: .milliseconds(350))
    let page = max(1, continuation?.page ?? 1)
    let url = try URL.endpoint(
      "https://api.vimeo.com/videos",
      queryItems: [
        URLQueryItem(name: "query", value: request.query),
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "per_page", value: String(max(1, min(request.pageSize, 50)))),
        URLQueryItem(name: "sort", value: "relevant"),
        URLQueryItem(name: "direction", value: "desc"),
      ])
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/vnd.vimeo.*+json;version=3.4", forHTTPHeaderField: "Accept")
    let response = try await HTTPClient.shared.decode(
      VimeoSearchResponse.self, request: urlRequest, maxRetries: 1)
    let assets = response.data.enumerated().compactMap { index, item in
      Self.asset(item, query: request.query, index: index)
    }
    return ProviderPage(
      assets: assets,
      continuation: response.paging.next == nil ? nil : .nextPage(page + 1),
      totalResults: response.total)
  }

  static func asset(_ item: VimeoVideo, query: String, index: Int) -> MediaAsset? {
    guard let source = URLValidator.remote(item.link) else { return nil }
    let rights = vimeoRights(item.license)
    let orderedPictures = (item.pictures?.sizes ?? []).sorted {
      ($0.width ?? 0) * ($0.height ?? 0) > ($1.width ?? 0) * ($1.height ?? 0)
    }
    let thumbnails = ThumbnailResolver.candidates(
      provider: .vimeo, rawValues: orderedPictures.map(\.link), originalPageURL: source)
    let id = item.uri.split(separator: "/").last.map(String.init) ?? item.uri
    return MediaAsset(
      id: id, provider: .vimeo, title: item.name,
      description: ProviderUtilities.cleanHTML(item.description),
      thumbnailURL: thumbnails.first, previewURL: nil, downloadURL: nil,
      sourcePageURL: source, creator: item.user?.name, license: rights.statement,
      licenseURL: rights.uri, licenseStatus: vimeoLicenseStatus(item.license),
      width: item.width, height: item.height, duration: item.duration, fileType: "Vimeo",
      mediaType: .video,
      publishedDate: ProviderUtilities.parseDate(item.releaseTime ?? item.createdTime),
      downloadable: false,
      originalMetadata: [
        "privacyDownload": item.privacy?.download.map(String.init) ?? "unknown",
        "discoveryOnly": "true",
      ], searchKeyword: query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: .unavailable,
      thumbnailCandidates: thumbnails)
  }
}

private func vimeoLicenseStatus(_ value: String?) -> LicenseStatus {
  guard let value else { return .unknown }
  if value == "cc0" { return .publicDomain }
  if value.contains("-nc") || value.contains("-nd") { return .restricted }
  if value == "by" || value == "by-sa" { return .attributionRequired }
  return .unknown
}

private func vimeoRights(_ value: String?) -> RightsInfo {
  guard let value, !value.isEmpty else {
    return RightsInfo(statement: nil, source: "Vimeo video metadata", known: false)
  }
  if value == "cc0" {
    return RightsInfo(
      statement: "CC0",
      uri: URLValidator.remote("https://creativecommons.org/publicdomain/zero/1.0/"),
      source: "Vimeo video metadata", known: true, publicDomain: true, openLicense: true)
  }
  let names: [String: String] = [
    "by": "CC BY", "by-sa": "CC BY-SA", "by-nd": "CC BY-ND", "by-nc": "CC BY-NC",
    "by-nc-sa": "CC BY-NC-SA", "by-nc-nd": "CC BY-NC-ND",
  ]
  guard let name = names[value] else {
    return RightsInfo(statement: value, source: "Vimeo video metadata", known: true)
  }
  let status = vimeoLicenseStatus(value)
  return RightsInfo(
    statement: name, uri: URLValidator.remote("https://creativecommons.org/licenses/\(value)/4.0/"),
    source: "Vimeo video metadata", known: true, openLicense: status == .attributionRequired,
    attributionRequired: true, commercialUseKnown: value.contains("-nc") ? false : true)
}

struct VimeoSearchResponse: Decodable {
  let total: Int?
  let data: [VimeoVideo]
  let paging: VimeoPaging
}

struct VimeoPaging: Decodable { let next, previous, first, last: String? }

struct VimeoVideo: Decodable {
  let uri, name, link: String
  let description, license, createdTime, releaseTime: String?
  let duration: Double?
  let width, height: Int?
  let user: VimeoUser?
  let pictures: VimeoPictures?
  let privacy: VimeoPrivacy?
  enum CodingKeys: String, CodingKey {
    case uri, name, link, description, license, duration, width, height, user, pictures, privacy
    case createdTime = "created_time"
    case releaseTime = "release_time"
  }
}

struct VimeoUser: Decodable { let name: String? }
struct VimeoPictures: Decodable { let sizes: [VimeoPicture] }
struct VimeoPicture: Decodable {
  let width, height: Int?
  let link: String?
}
struct VimeoPrivacy: Decodable { let download: Bool? }

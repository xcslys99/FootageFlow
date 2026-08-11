import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Searches the public PeerTube index operated by SepiaSearch. Results remain discovery-only
/// unless a source explicitly supplies reusable/downloadable media through a future detail adapter.
struct PeerTubeProvider: MediaProvider {
  let info = ProviderInfo(
    id: .peertube, displayName: "PeerTube / SepiaSearch", mode: .publicAPI,
    requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .bestEffort, metadata: .supported, license: .bestEffort,
      download: .unavailable, supportsVideo: true, supportsImage: false,
      pagination: .supported, accessMethods: [.publicAPI, .publicInterface]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard request.mediaType == .video || request.mediaType == .all else {
      return ProviderPage(assets: [], continuation: nil)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .peertube, minimumInterval: .milliseconds(300))
    let count = max(1, min(request.pageSize, 40))
    let start = max(0, continuation?.offset ?? 0)
    var queryItems = [
      URLQueryItem(name: "search", value: request.query),
      URLQueryItem(name: "count", value: String(count)),
      URLQueryItem(name: "start", value: String(start)),
      URLQueryItem(name: "nsfw", value: "false"),
    ]
    if request.duration != .all {
      switch request.duration {
      case .underMinute:
        queryItems.append(URLQueryItem(name: "durationMax", value: "59"))
      case .oneToFive:
        queryItems += [
          URLQueryItem(name: "durationMin", value: "60"),
          URLQueryItem(name: "durationMax", value: "299"),
        ]
      case .fiveToTwenty:
        queryItems += [
          URLQueryItem(name: "durationMin", value: "300"),
          URLQueryItem(name: "durationMax", value: "1199"),
        ]
      case .overTwenty:
        queryItems.append(URLQueryItem(name: "durationMin", value: "1200"))
      case .all: break
      }
    }
    let url = try URL.endpoint(
      "https://sepiasearch.org/api/v1/search/videos", queryItems: queryItems)
    let response = try await HTTPClient.shared.decode(
      PeerTubeSearchResponse.self, request: URLRequest(url: url), maxRetries: 1)
    let assets = response.data.enumerated().compactMap { index, item in
      Self.asset(item, query: request.query, index: index)
    }
    let nextOffset = start + response.data.count
    return ProviderPage(
      assets: assets,
      continuation: nextOffset < response.total && !response.data.isEmpty
        ? ProviderContinuation(offset: nextOffset) : nil,
      totalResults: response.total)
  }

  static func asset(_ item: PeerTubeVideo, query: String, index: Int) -> MediaAsset? {
    guard let source = URLValidator.remote(item.url) else { return nil }
    let license = item.licence?.label?.nilIfEmpty
    let licenseStatus =
      license?.localizedCaseInsensitiveContains("unknown") == true
      ? LicenseStatus.unknown : ProviderUtilities.licenseStatus(name: license)
    let creator = item.channel?.displayName ?? item.account?.displayName ?? item.account?.name
    let instance =
      ThumbnailResolver.origin(fromHost: item.channel?.host ?? item.account?.host)
      ?? ThumbnailResolver.origin(from: source)
    let listedThumbnails = (item.thumbnails ?? []).sorted {
      ($0.width ?? 0) * ($0.height ?? 0) > ($1.width ?? 0) * ($1.height ?? 0)
    }
    let candidates = ThumbnailResolver.candidates(
      provider: .peertube,
      rawValues: listedThumbnails.map(\.fileUrl)
        + listedThumbnails.map(\.path)
        + [item.thumbnailUrl, item.thumbnailPath]
        + [item.previewUrl, item.previewPath],
      originalPageURL: source, instanceURL: instance,
      metadata: ["instanceHost": instance?.host ?? ""])
    let thumbnail = candidates.first
    let rights = RightsInfo(
      statement: licenseStatus == .unknown ? nil : license,
      source: "PeerTube video metadata", known: licenseStatus != .unknown,
      publicDomain: licenseStatus == .publicDomain,
      openLicense: [.safe, .attributionRequired, .publicDomain].contains(licenseStatus),
      attributionRequired: licenseStatus == .attributionRequired)
    return MediaAsset(
      id: item.uuid, provider: .peertube, title: item.name,
      description: ProviderUtilities.cleanHTML(item.description ?? item.truncatedDescription),
      thumbnailURL: thumbnail, previewURL: nil, downloadURL: nil, sourcePageURL: source,
      creator: creator, license: licenseStatus == .unknown ? nil : license,
      licenseURL: nil, licenseStatus: licenseStatus, width: nil, height: nil,
      duration: item.duration, fileType: "PeerTube", mediaType: .video,
      publishedDate: ProviderUtilities.parseDate(item.originallyPublishedAt ?? item.publishedAt),
      downloadable: false,
      originalMetadata: [
        "host": source.host ?? "", "instanceHost": instance?.host ?? "", "uuid": item.uuid,
        "thumbnailRaw": item.thumbnailUrl ?? item.thumbnailPath ?? "",
        "views": item.views.map(String.init) ?? "",
      ], searchKeyword: query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: .unavailable,
      thumbnailCandidates: candidates)
  }
}

struct PeerTubeSearchResponse: Decodable {
  let total: Int
  let data: [PeerTubeVideo]
}

struct PeerTubeVideo: Decodable {
  let uuid, name, url: String
  let description, truncatedDescription, thumbnailUrl, thumbnailPath: String?
  let previewUrl, previewPath: String?
  let publishedAt, originallyPublishedAt: String?
  let duration: Double?
  let views: Int?
  let licence: PeerTubeLabel?
  let account, channel: PeerTubeOwner?
  let thumbnails: [PeerTubeThumbnail]?
}

struct PeerTubeThumbnail: Decodable {
  let fileUrl, path: String?
  let width, height: Int?
}

struct PeerTubeLabel: Decodable {
  let id: Int?
  let label: String?
}

struct PeerTubeOwner: Decodable {
  let name, displayName, url, host: String?
}

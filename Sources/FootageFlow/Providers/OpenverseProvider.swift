import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Anonymous access is the Openverse-recommended default for ordinary interactive search.
/// The provider never assumes that an Openverse result is public domain: the API's per-item
/// license metadata is preserved and normalized into FootageFlow's rights model.
struct OpenverseProvider: MediaProvider {
  let info = ProviderInfo(
    id: .openverse, displayName: "Openverse", mode: .publicAPI, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .supported,
      download: .supported, supportsVideo: false, supportsImage: true, supportsAudio: true,
      pagination: .supported, accessMethods: [.officialAPI, .publicAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard request.mediaType != .video else {
      return ProviderPage(assets: [], continuation: nil, totalResults: 0)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .openverse, minimumInterval: .milliseconds(350))
    let page = max(1, continuation?.page ?? 1)
    let pageSize = max(1, min(request.pageSize, 20))
    let types: [MediaType] = request.mediaType == .all ? [.image, .audio] : [request.mediaType]

    var responses: [(MediaType, OpenverseSearchResponse)] = []
    try await withThrowingTaskGroup(of: (MediaType, OpenverseSearchResponse).self) { group in
      for type in types {
        group.addTask {
          let endpoint = type == .audio ? "audio" : "images"
          let url = try URL.endpoint(
            "https://api.openverse.org/v1/\(endpoint)/",
            queryItems: [
              URLQueryItem(name: "q", value: request.query),
              URLQueryItem(name: "page_size", value: String(pageSize)),
              URLQueryItem(name: "page", value: String(page)),
            ])
          let value = try await HTTPClient.shared.decode(
            OpenverseSearchResponse.self, request: URLRequest(url: url), maxRetries: 1)
          return (type, value)
        }
      }
      for try await response in group { responses.append(response) }
    }

    var assets: [MediaAsset] = []
    var total = 0
    var hasMore = false
    for (type, response) in responses {
      total += response.resultCount
      hasMore = hasMore || page < response.pageCount
      assets += response.results.enumerated().compactMap { index, item in
        Self.asset(item, type: type, query: request.query, index: index)
      }
    }
    assets.sort { $0.relevanceScore > $1.relevanceScore }
    return ProviderPage(
      assets: assets, continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: total)
  }

  static func asset(
    _ item: OpenverseResult, type: MediaType, query: String, index: Int
  ) -> MediaAsset? {
    guard let source = ProviderUtilities.safeURL(item.foreignLandingURL) else { return nil }
    let download = ProviderUtilities.safeURL(item.url)
    let licenseURL = ProviderUtilities.safeURL(item.licenseURL)
    let licenseName = licenseDisplayName(item.license, version: item.licenseVersion)
    let status = licenseStatus(item.license)
    let publicDomain = status == .publicDomain
    let openLicense = item.license?.lowercased().hasPrefix("by") == true || publicDomain
    let attributionRequired = openLicense && !publicDomain
    let rights = RightsInfo(
      statement: licenseName, uri: licenseURL, source: "Openverse item metadata",
      known: licenseName != nil, publicDomain: publicDomain, openLicense: openLicense,
      attributionRequired: attributionRequired,
      commercialUseKnown: commercialUseKnown(item.license))
    let candidates = ThumbnailResolver.candidates(
      provider: .openverse, rawValues: [item.thumbnail], originalPageURL: source)
    var metadata = [
      "sourceName": "Openverse", "openverseProvider": item.provider ?? "",
      "openverseSource": item.source ?? "", "attribution": item.attribution ?? "",
      "licenseCode": item.license ?? "",
      "tags": (item.tags ?? []).compactMap(\.name).joined(separator: ", "),
    ]
    if type == .audio { metadata["durationUnit"] = "milliseconds" }
    return MediaAsset(
      id: item.id, provider: .openverse, title: item.title?.nilIfEmpty ?? tr("common.unknown"),
      description: nil, thumbnailURL: candidates.first,
      previewURL: type == .image ? download : nil, downloadURL: download,
      sourcePageURL: source, creator: item.creator?.nilIfEmpty, license: licenseName,
      licenseURL: licenseURL, licenseStatus: status, width: item.width, height: item.height,
      duration: type == .audio ? normalizedDuration(item.duration) : nil,
      fileType: item.filetype?.nilIfEmpty ?? download?.pathExtension.nilIfEmpty,
      mediaType: type, publishedDate: nil, downloadable: download != nil,
      originalMetadata: metadata, searchKeyword: query,
      relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights,
      downloadAvailability: download == nil ? .unavailable : .direct,
      thumbnailCandidates: candidates)
  }

  private static func normalizedDuration(_ value: Double?) -> Double? {
    guard let value, value >= 0 else { return nil }
    // Openverse audio duration is defined and returned in milliseconds,
    // including sub-ten-second clips whose raw value is below 10,000.
    return value / 1_000
  }

  private static func licenseDisplayName(_ code: String?, version: String?) -> String? {
    guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
      return nil
    }
    let normalized = code.lowercased()
    let name: String
    if normalized == "pdm" {
      name = "Public Domain Mark"
    } else if normalized == "cc0" {
      name = "CC0"
    } else {
      name = "CC \(normalized.uppercased())"
    }
    guard let version = version?.nilIfEmpty, normalized != "pdm" else { return name }
    return "\(name) \(version)"
  }

  private static func licenseStatus(_ code: String?) -> LicenseStatus {
    let value = code?.lowercased() ?? ""
    if value == "pdm" || value == "cc0" { return .publicDomain }
    if value.contains("-nc") || value.contains("-nd") { return .restricted }
    if value == "by" || value.hasPrefix("by-") { return .attributionRequired }
    return .unknown
  }

  private static func commercialUseKnown(_ code: String?) -> Bool? {
    guard let value = code?.lowercased(), !value.isEmpty else { return nil }
    if value.contains("-nc") { return false }
    if value == "pdm" || value == "cc0" || value == "by" || value.hasPrefix("by-") {
      return true
    }
    return nil
  }
}

struct OpenverseSearchResponse: Decodable {
  let resultCount, pageCount: Int
  let results: [OpenverseResult]

  enum CodingKeys: String, CodingKey {
    case resultCount = "result_count"
    case pageCount = "page_count"
    case results
  }
}

struct OpenverseResult: Decodable {
  let id: String
  let title, creator, license, licenseVersion, licenseURL: String?
  let thumbnail, url, foreignLandingURL, filetype, provider, source, attribution: String?
  let width, height: Int?
  let duration: Double?
  let tags: [OpenverseTag]?

  enum CodingKeys: String, CodingKey {
    case id, title, creator, license, thumbnail, url, width, height, duration, filetype, provider,
      source, attribution, tags
    case licenseVersion = "license_version"
    case licenseURL = "license_url"
    case foreignLandingURL = "foreign_landing_url"
  }
}

struct OpenverseTag: Decodable { let name: String? }

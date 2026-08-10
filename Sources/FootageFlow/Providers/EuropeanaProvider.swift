import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct EuropeanaProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .europeana, displayName: "Europeana", mode: .officialAPI, requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .supported,
      download: .bestEffort, supportsVideo: true, supportsImage: true, supportsAudio: true,
      accessMethods: [.officialAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.missingAPIKey(.europeana)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .europeana, minimumInterval: .milliseconds(250))
    var queryItems = [
      URLQueryItem(name: "query", value: request.query),
      URLQueryItem(name: "rows", value: String(min(request.pageSize, 40))),
      URLQueryItem(name: "media", value: "true"),
      URLQueryItem(name: "thumbnail", value: "true"),
      URLQueryItem(name: "landingpage", value: "true"),
    ]
    if request.mediaType != .all {
      queryItems.append(
        URLQueryItem(name: "qf", value: "TYPE:\(request.mediaType.rawValue.uppercased())"))
    }
    if request.yearFrom != nil || request.yearTo != nil {
      queryItems.append(
        URLQueryItem(
          name: "qf",
          value:
            "YEAR:[\(request.yearFrom.map(String.init) ?? "*") TO \(request.yearTo.map(String.init) ?? "*")]"
        ))
    }
    let url = try URL.endpoint(
      "https://api.europeana.eu/record/v2/search.json", queryItems: queryItems)
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
    let response = try await HTTPClient.shared.decode(
      EuropeanaSearchResponse.self, request: urlRequest, maxRetries: 1)
    guard response.success != false else { throw ProviderError.invalidResponse }
    return response.items.enumerated().compactMap { index, item in
      Self.asset(item, query: request.query, index: index)
    }
  }

  static func asset(_ item: EuropeanaItem, query: String, index: Int) -> MediaAsset? {
    let type = MediaType(rawValue: item.type?.lowercased() ?? "") ?? .image
    let source =
      (item.edmIsShownAt ?? []).compactMap(URLValidator.remote).first
      ?? URLValidator.remote(item.guid)
      ?? URLValidator.remote("https://www.europeana.eu/item\(item.id)")
    guard let source else { return nil }
    let direct = (item.edmIsShownBy ?? []).compactMap(URLValidator.remote).first(where: mediaURL)
    let thumbnail = (item.edmPreview ?? []).compactMap(URLValidator.remote).first
    let rightsText = (item.edmRights ?? item.rights ?? []).first
    let rightsURL = URLValidator.remote(rightsText)
    let rightsName = ProviderUtilities.licenseName(name: rightsText, url: rightsText)
    let status = ProviderUtilities.licenseStatus(name: rightsName, url: rightsText)
    let rights = RightsInfo(
      statement: rightsName, uri: rightsURL, source: "Europeana item metadata",
      known: rightsText != nil, publicDomain: status == .publicDomain,
      openLicense: [.safe, .attributionRequired, .publicDomain].contains(status),
      attributionRequired: status == .attributionRequired)
    let title = item.title?.first?.nilIfEmpty ?? "Europeana \(item.id)"
    return MediaAsset(
      id: item.id, provider: .europeana, title: title,
      description: ProviderUtilities.cleanHTML(item.dcDescription?.first),
      thumbnailURL: thumbnail, previewURL: type == .image ? (thumbnail ?? direct) : direct,
      downloadURL: direct, sourcePageURL: source, creator: item.dcCreator?.first,
      license: rightsName, licenseURL: rightsURL, licenseStatus: status,
      width: nil, height: nil, duration: nil,
      fileType: direct?.pathExtension.nilIfEmpty, mediaType: type,
      publishedDate: ProviderUtilities.parseDate(item.year?.first),
      downloadable: direct != nil,
      originalMetadata: [
        "dataProvider": item.dataProvider?.first ?? "",
        "country": item.country?.first ?? "",
      ], searchKeyword: query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: direct == nil ? .unavailable : .direct)
  }

  private static func mediaURL(_ url: URL) -> Bool {
    ["mp4", "mov", "m4v", "webm", "jpg", "jpeg", "png", "tif", "tiff", "mp3", "wav", "m4a"]
      .contains(url.pathExtension.lowercased())
  }
}

struct EuropeanaSearchResponse: Decodable {
  let success: Bool?
  let items: [EuropeanaItem]
}
struct EuropeanaItem: Decodable {
  let id: String
  let guid, type: String?
  let title, dcDescription, dcCreator, edmPreview, edmIsShownAt, edmIsShownBy: [String]?
  let edmRights, rights, year, dataProvider, country: [String]?
}

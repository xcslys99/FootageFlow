import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct NASAProvider: MediaProvider {
  let info = ProviderInfo(
    id: .nasa, displayName: "NASA", mode: .publicAPI, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .bestEffort,
      download: .supported, supportsVideo: true, supportsImage: true, supportsAudio: true,
      pagination: .supported,
      accessMethods: [.officialAPI, .publicAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    try await ProviderRequestLimiter.shared.wait(for: .nasa, minimumInterval: .milliseconds(250))
    let page = max(1, continuation?.page ?? 1)
    var queryItems = [
      URLQueryItem(name: "q", value: request.query),
      URLQueryItem(name: "page_size", value: String(min(request.pageSize, 24))),
      URLQueryItem(name: "page", value: String(page)),
    ]
    if request.mediaType != .all {
      queryItems.append(URLQueryItem(name: "media_type", value: request.mediaType.rawValue))
    }
    if let year = request.yearFrom {
      queryItems.append(URLQueryItem(name: "year_start", value: "\(year)"))
    }
    if let year = request.yearTo {
      queryItems.append(URLQueryItem(name: "year_end", value: "\(year)"))
    }
    let url = try URL.endpoint("https://images-api.nasa.gov/search", queryItems: queryItems)
    let response = try await HTTPClient.shared.decode(
      NASASearchResponse.self, request: URLRequest(url: url))
    let indexed = Array(response.collection.items.prefix(min(request.pageSize, 24)).enumerated())
    var assets: [MediaAsset] = []
    for start in stride(from: 0, to: indexed.count, by: 4) {
      let batch = indexed[start..<min(start + 4, indexed.count)]
      let resolved = await withTaskGroup(of: MediaAsset?.self, returning: [MediaAsset].self) {
        group in
        for (index, item) in batch {
          group.addTask { await Self.asset(item, query: request.query, index: index) }
        }
        var output: [MediaAsset] = []
        for await value in group { if let value { output.append(value) } }
        return output
      }
      assets += resolved
    }
    let sorted = assets.sorted { $0.relevanceScore > $1.relevanceScore }
    let hasMore = response.collection.links?.contains { $0.rel == "next" } == true
    return ProviderPage(
      assets: sorted, continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: response.collection.metadata?.totalHits)
  }

  static func asset(_ item: NASAItem, query: String, index: Int) async -> MediaAsset? {
    var manifest: [String] = []
    if let manifestURL = secureURL(item.href) {
      do {
        manifest = try await HTTPClient.shared.decode(
          [String].self, request: URLRequest(url: manifestURL), maxRetries: 1)
      } catch {
        manifest = []
      }
    }
    return asset(item, manifest: manifest, query: query, index: index)
  }

  static func asset(_ item: NASAItem, manifest: [String], query: String, index: Int)
    -> MediaAsset?
  {
    guard let data = item.data.first,
      let source = URLValidator.remote(
        "https://images.nasa.gov/details/\(pathComponent(data.nasaID))")
    else { return nil }
    let type = MediaType(rawValue: data.mediaType) ?? .image
    let candidateURLs = manifest.compactMap(secureURL)
    let downloadable = bestAsset(in: candidateURLs, type: type)
    let preview =
      previewAsset(in: candidateURLs, type: type) ?? (type == .image ? downloadable : nil)
    let thumbnail =
      item.links?.first(where: { $0.rel == "preview" }).flatMap { secureURL($0.href) }
      ?? item.links?.first.flatMap { secureURL($0.href) }
    let creator = data.photographer?.nilIfEmpty ?? data.secondaryCreator?.nilIfEmpty
    let metadata = [
      "nasaID": data.nasaID, "center": data.center ?? "", "location": data.location ?? "",
      "keywords": (data.keywords ?? []).joined(separator: ", "),
    ]
    return MediaAsset(
      id: data.nasaID, provider: .nasa, title: data.title,
      description: ProviderUtilities.cleanHTML(data.description), thumbnailURL: thumbnail,
      previewURL: preview, downloadURL: downloadable, sourcePageURL: source, creator: creator,
      license: nil, licenseURL: nil, licenseStatus: .unknown, width: nil, height: nil,
      duration: duration(in: data.description), fileType: downloadable?.pathExtension.nilIfEmpty,
      mediaType: type, publishedDate: ProviderUtilities.parseDate(data.dateCreated),
      downloadable: downloadable != nil, originalMetadata: metadata, searchKeyword: query,
      relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: RightsInfo(statement: nil, source: "NASA item metadata", known: false),
      downloadAvailability: downloadable == nil ? .unavailable : .direct)
  }

  private static func pathComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
  }

  private static func secureURL(_ value: String?) -> URL? {
    guard var components = value.flatMap(URLComponents.init(string:)) else { return nil }
    if components.scheme == "http" { components.scheme = "https" }
    return components.url.flatMap { try? URLValidator.remote($0) }
  }

  private static func bestAsset(in values: [URL], type: MediaType) -> URL? {
    let extensions = extensions(for: type)
    let matching = values.filter { extensions.contains($0.pathExtension.lowercased()) }
    return matching.first(where: { $0.lastPathComponent.lowercased().contains("~orig") })
      ?? matching.first(where: { !$0.lastPathComponent.lowercased().contains("preview") })
      ?? matching.first
  }

  private static func previewAsset(in values: [URL], type: MediaType) -> URL? {
    let matching = values.filter { extensions(for: type).contains($0.pathExtension.lowercased()) }
    return matching.first(where: { $0.lastPathComponent.lowercased().contains("preview") })
      ?? matching.first(where: { $0.lastPathComponent.lowercased().contains("small") })
  }

  private static func extensions(for type: MediaType) -> Set<String> {
    switch type {
    case .video: ["mp4", "mov", "m4v", "webm"]
    case .audio: ["mp3", "wav", "m4a", "aac"]
    case .image: ["jpg", "jpeg", "png", "tif", "tiff"]
    case .all: []
    }
  }

  private static func duration(in description: String?) -> Double? {
    guard let description,
      let expression = try? NSRegularExpression(
        pattern: #"(?:TRT|Duration):?\s*(\d{1,2}):(\d{2}):(\d{2})"#,
        options: .caseInsensitive),
      let match = expression.firstMatch(
        in: description, range: NSRange(description.startIndex..., in: description)),
      let hourRange = Range(match.range(at: 1), in: description),
      let minuteRange = Range(match.range(at: 2), in: description),
      let secondRange = Range(match.range(at: 3), in: description),
      let hours = Double(description[hourRange]), let minutes = Double(description[minuteRange]),
      let seconds = Double(description[secondRange])
    else { return nil }
    return hours * 3_600 + minutes * 60 + seconds
  }
}

struct NASASearchResponse: Decodable { let collection: NASACollection }
struct NASACollection: Decodable {
  let items: [NASAItem]
  let links: [NASALink]?
  let metadata: NASAMetadata?
}
struct NASAMetadata: Decodable {
  let totalHits: Int?
  enum CodingKeys: String, CodingKey { case totalHits = "total_hits" }
}
struct NASAItem: Decodable {
  let href: String?
  let data: [NASAData]
  let links: [NASALink]?
}
struct NASAData: Decodable {
  let nasaID, title, mediaType: String
  let description, dateCreated, center, photographer, secondaryCreator, location: String?
  let keywords: [String]?
  enum CodingKeys: String, CodingKey {
    case title, description, center, photographer, keywords, location
    case nasaID = "nasa_id"
    case mediaType = "media_type"
    case dateCreated = "date_created"
    case secondaryCreator = "secondary_creator"
  }
}
struct NASALink: Decodable { let href, rel: String? }

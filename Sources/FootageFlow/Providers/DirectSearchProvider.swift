import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

protocol DirectSearchPageLoading: Sendable {
  func load(_ url: URL, provider: ProviderID) async throws -> String
}

struct LiveDirectSearchPageLoader: DirectSearchPageLoading {
  func load(_ url: URL, provider: ProviderID) async throws -> String {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    do {
      let (data, _) = try await HTTPClient.shared.data(for: request, maxRetries: 0)
      guard data.count <= 8_000_000 else { throw ProviderError.invalidResponse }
      guard let html = String(data: data, encoding: .utf8) else {
        throw ProviderError.invalidResponse
      }
      return html
    } catch ProviderError.invalidAPIKey {
      // A public page returning 401/403 is a temporary direct-search block, not an API-key error.
      throw ProviderError.temporarilyBlocked(provider)
    }
  }
}

struct PexelsDirectProvider: MediaProvider {
  let loader: any DirectSearchPageLoading
  let info = ProviderInfo(
    id: .pexels, displayName: "Pexels", mode: .directSearch, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .bestEffort, preview: .bestEffort, metadata: .bestEffort, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: true,
      accessMethods: [.officialAPI, .directSearch]))

  init(loader: any DirectSearchPageLoading = LiveDirectSearchPageLoader()) {
    self.loader = loader
  }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await DirectSearchEngine.search(provider: .pexels, request: request, loader: loader)
  }
}

struct PixabayDirectProvider: MediaProvider {
  let loader: any DirectSearchPageLoading
  let info = ProviderInfo(
    id: .pixabay, displayName: "Pixabay", mode: .directSearch, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .bestEffort, preview: .bestEffort, metadata: .bestEffort, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: true,
      accessMethods: [.officialAPI, .directSearch]))

  init(loader: any DirectSearchPageLoading = LiveDirectSearchPageLoader()) {
    self.loader = loader
  }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await DirectSearchEngine.search(provider: .pixabay, request: request, loader: loader)
  }
}

enum DirectSearchEngine {
  static func search(
    provider: ProviderID, request: SearchRequest, loader: any DirectSearchPageLoading
  ) async throws -> [MediaAsset] {
    guard request.mediaType != .audio else { return [] }
    let targets = try targetURLs(provider: provider, request: request)
    var assets: [MediaAsset] = []
    var firstError: Error?
    await withTaskGroup(of: Result<[MediaAsset], Error>.self) { group in
      for target in targets {
        group.addTask {
          do {
            let html = try await loader.load(target.url, provider: provider)
            let parsed = DirectSearchHTMLParser.parse(
              html: html, provider: provider, expectedType: target.type,
              query: request.query, limit: request.pageSize)
            if parsed.isEmpty && !DirectSearchHTMLParser.indicatesNoResults(html) {
              throw ProviderError.temporarilyBlocked(provider)
            }
            return .success(parsed)
          } catch {
            return .failure(error)
          }
        }
      }
      for await result in group {
        switch result {
        case .success(let found): assets += found
        case .failure(let error): if firstError == nil { firstError = error }
        }
      }
    }
    let deduplicated = SearchDeduplicator.apply(assets)
    if deduplicated.isEmpty, let firstError { throw firstError }
    return Array(deduplicated.prefix(request.pageSize))
  }

  private static func targetURLs(provider: ProviderID, request: SearchRequest) throws -> [Target] {
    let query = pathSegment(request.query)
    let types: [MediaType] =
      switch request.mediaType {
      case .all: [.video, .image]
      case .video: [.video]
      case .image: [.image]
      case .audio: []
      }
    return try types.map { type in
      let value: String
      switch (provider, type) {
      case (.pexels, .video): value = "https://www.pexels.com/search/videos/\(query)/"
      case (.pexels, .image): value = "https://www.pexels.com/search/\(query)/"
      case (.pixabay, .video): value = "https://pixabay.com/videos/search/\(query)/"
      case (.pixabay, .image): value = "https://pixabay.com/images/search/\(query)/"
      default: throw ProviderError.unsupported
      }
      return Target(url: try URLValidator.remote(URL(string: value)), type: type)
    }
  }

  private static func pathSegment(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~ ")
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
      .addingPercentEncoding(withAllowedCharacters: allowed)?
      .replacingOccurrences(of: "%20", with: "-") ?? "search"
  }

  private struct Target: Sendable {
    let url: URL
    let type: MediaType
  }
}

enum DirectSearchHTMLParser {
  static func indicatesNoResults(_ html: String) -> Bool {
    let value = html.lowercased()
    return ["no results", "0 results", "nothing found", "没有结果", "未找到"]
      .contains { value.contains($0) }
  }

  static func parse(
    html: String, provider: ProviderID, expectedType: MediaType, query: String, limit: Int
  ) -> [MediaAsset] {
    var output = jsonAssets(
      html: html, provider: provider, expectedType: expectedType, query: query)
    output += anchorAssets(
      html: html, provider: provider, expectedType: expectedType, query: query)
    return Array(SearchDeduplicator.apply(output).prefix(max(1, limit)))
  }

  private static func jsonAssets(
    html: String, provider: ProviderID, expectedType: MediaType, query: String
  ) -> [MediaAsset] {
    let pattern = #"(?is)<script[^>]*(?:application/ld\+json|__NEXT_DATA__)[^>]*>(.*?)</script>"#
    return matches(pattern, in: html).flatMap { match -> [MediaAsset] in
      guard let data = unescape(match).data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data)
      else { return [] }
      var dictionaries: [[String: Any]] = []
      collectDictionaries(root, into: &dictionaries)
      return dictionaries.compactMap {
        asset(from: $0, provider: provider, expectedType: expectedType, query: query)
      }
    }
  }

  private static func anchorAssets(
    html: String, provider: ProviderID, expectedType: MediaType, query: String
  ) -> [MediaAsset] {
    let pattern = #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
    return capturePairs(pattern, in: html).enumerated().compactMap { index, pair in
      guard let source = absoluteURL(pair.0, provider: provider),
        let type = assetType(source, provider: provider), type == expectedType
      else { return nil }
      let body = pair.1
      let title =
        firstAttribute(["alt", "aria-label", "title"], in: body)
        ?? source.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
      let thumbnailText =
        largestSource(in: body)
        ?? firstAttribute(["poster", "data-lazy-src", "data-src", "src"], in: body)
      let thumbnail = thumbnailText.flatMap { remoteResource($0, relativeTo: source) }
      let direct =
        directMediaURL(in: body, relativeTo: source, expectedType: type)
        ?? (type == .image ? thumbnail : nil)
      let dimensions = dimensions(in: body)
      return makeAsset(
        provider: provider, source: source, direct: direct, thumbnail: thumbnail, type: type,
        title: unescape(title), creator: nil, width: dimensions.0, height: dimensions.1,
        duration: nil, query: query, rank: index)
    }
  }

  private static func asset(
    from dictionary: [String: Any], provider: ProviderID, expectedType: MediaType, query: String
  ) -> MediaAsset? {
    let typeText = string(dictionary["@type"])?.lowercased() ?? ""
    let inferred: MediaType = typeText.contains("video") ? .video : expectedType
    guard inferred == expectedType else { return nil }
    let sourceText = string(dictionary["url"]) ?? string(dictionary["mainEntityOfPage"])
    guard let sourceText, let source = absoluteURL(sourceText, provider: provider),
      assetType(source, provider: provider) != nil
    else { return nil }
    let directText = string(dictionary["contentUrl"]) ?? string(dictionary["contentURL"])
    let thumbnailText =
      string(dictionary["thumbnailUrl"])
      ?? string(dictionary["thumbnailURL"]) ?? string(dictionary["image"])
    let direct = directText.flatMap { remoteResource($0, relativeTo: source) }
    let thumbnail = thumbnailText.flatMap { remoteResource($0, relativeTo: source) }
    let author = dictionary["author"] as? [String: Any]
    let creator = string(author?["name"]) ?? string(dictionary["creator"])
    let title =
      string(dictionary["name"]) ?? string(dictionary["caption"])
      ?? source.lastPathComponent.replacingOccurrences(of: "-", with: " ")
    return makeAsset(
      provider: provider, source: source, direct: direct ?? (inferred == .image ? thumbnail : nil),
      thumbnail: thumbnail, type: inferred, title: unescape(title), creator: creator,
      width: integer(dictionary["width"]), height: integer(dictionary["height"]),
      duration: isoDuration(string(dictionary["duration"])), query: query, rank: 0)
  }

  private static func makeAsset(
    provider: ProviderID, source: URL, direct: URL?, thumbnail: URL?, type: MediaType,
    title: String, creator: String?, width: Int?, height: Int?, duration: Double?, query: String,
    rank: Int
  ) -> MediaAsset {
    let id = source.path.split(separator: "/").last.map(String.init) ?? source.absoluteString
    // Direct-page markup is not a reliable license API. Keep the source policy link, but do not
    // infer that a particular item is cleared merely because its page could be discovered.
    let licenseName: String? = nil
    let licenseURL = URLValidator.remote(
      provider == .pexels
        ? "https://www.pexels.com/license/" : "https://pixabay.com/service/license-summary/")
    return MediaAsset(
      id: id, provider: provider, title: title, description: nil, thumbnailURL: thumbnail,
      previewURL: type == .video ? direct : (thumbnail ?? direct), downloadURL: direct,
      sourcePageURL: source, creator: creator, license: licenseName, licenseURL: licenseURL,
      licenseStatus: .unknown, width: width, height: height, duration: duration,
      fileType: direct.map { fileType($0, mediaType: type) }, mediaType: type,
      publishedDate: nil, downloadable: direct != nil,
      originalMetadata: ["accessMode": ProviderMode.directSearch.rawValue], searchKeyword: query,
      relevanceScore: 0.8 - Double(rank) * 0.01)
  }

  private static func assetType(_ url: URL, provider: ProviderID) -> MediaType? {
    let path = url.path.lowercased()
    guard !path.contains("/search/") else { return nil }
    switch provider {
    case .pexels:
      if path.contains("/video/") { return .video }
      if path.contains("/photo/") { return .image }
    case .pixabay:
      if path.contains("/videos/") { return .video }
      if path.contains("/photos/") || path.contains("/illustrations/")
        || path.contains("/vectors/")
      {
        return .image
      }
    default: break
    }
    return nil
  }

  private static func absoluteURL(_ value: String, provider: ProviderID) -> URL? {
    let host = provider == .pexels ? "www.pexels.com" : "pixabay.com"
    guard let base = URL(string: "https://\(host)") else { return nil }
    let decoded = unescape(value)
    let url = URL(string: decoded, relativeTo: base)?.absoluteURL
    let domain = host.replacingOccurrences(of: "www.", with: "")
    guard let url, let resolvedHost = url.host?.lowercased(),
      resolvedHost == domain || resolvedHost.hasSuffix(".\(domain)")
    else { return nil }
    return try? URLValidator.remote(url)
  }

  private static func remoteResource(_ value: String, relativeTo base: URL) -> URL? {
    let decoded = unescape(value)
    let normalized = decoded.hasPrefix("//") ? "https:\(decoded)" : decoded
    guard let url = URL(string: normalized, relativeTo: base)?.absoluteURL else { return nil }
    return try? URLValidator.remote(url)
  }

  private static func directMediaURL(
    in html: String, relativeTo base: URL, expectedType: MediaType
  ) -> URL? {
    let candidates = matches(#"(?i)(?:src|contentUrl)\s*=\s*[\"']([^\"']+)[\"']"#, in: html)
      .compactMap { remoteResource($0, relativeTo: base) }
    return candidates.first { url in
      let ext = url.pathExtension.lowercased()
      return expectedType == .video
        ? ["mp4", "webm", "mov", "m4v"].contains(ext)
        : ["jpg", "jpeg", "png", "webp"].contains(ext)
    }
  }

  private static func largestSource(in html: String) -> String? {
    guard let sourceSet = firstAttribute(["srcset"], in: html) else { return nil }
    return sourceSet.split(separator: ",").compactMap { part -> (String, Int)? in
      let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
      guard let first = pieces.first else { return nil }
      let width = pieces.dropFirst().first.flatMap { Int($0.dropLast()) } ?? 0
      return (String(first), width)
    }.max { $0.1 < $1.1 }?.0
  }

  private static func dimensions(in html: String) -> (Int?, Int?) {
    (
      firstAttribute(["width"], in: html).flatMap(Int.init),
      firstAttribute(["height"], in: html).flatMap(Int.init)
    )
  }

  private static func firstAttribute(_ names: [String], in html: String) -> String? {
    for name in names {
      let pattern =
        "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\"']([^\"']+)[\"']"
      if let value = matches(pattern, in: html).first { return value }
    }
    return nil
  }

  private static func collectDictionaries(_ value: Any, into output: inout [[String: Any]]) {
    if let dictionary = value as? [String: Any] {
      output.append(dictionary)
      for child in dictionary.values { collectDictionaries(child, into: &output) }
    } else if let array = value as? [Any] {
      for child in array { collectDictionaries(child, into: &output) }
    }
  }

  private static func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? [String] { return value.first }
    if let value = value as? [String: Any] { return string(value["url"]) ?? string(value["name"]) }
    return nil
  }

  private static func integer(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }

  private static func isoDuration(_ value: String?) -> Double? {
    guard let value else { return nil }
    let pattern = #"(?i)^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    else { return Double(value) }
    func component(_ index: Int) -> Double {
      guard let range = Range(match.range(at: index), in: value) else { return 0 }
      return Double(value[range]) ?? 0
    }
    return component(1) * 3600 + component(2) * 60 + component(3)
  }

  private static func fileType(_ url: URL, mediaType: MediaType) -> String {
    let ext = url.pathExtension.lowercased()
    if !ext.isEmpty { return ext }
    return mediaType == .video ? "video" : "image"
  }

  private static func matches(_ pattern: String, in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
      guard $0.numberOfRanges > 1, let range = Range($0.range(at: 1), in: value) else { return nil }
      return String(value[range])
    }
  }

  private static func capturePairs(_ pattern: String, in value: String) -> [(String, String)] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
      guard $0.numberOfRanges > 2, let first = Range($0.range(at: 1), in: value),
        let second = Range($0.range(at: 2), in: value)
      else { return nil }
      return (String(value[first]), String(value[second]))
    }
  }

  private static func unescape(_ value: String) -> String {
    value.replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
  }
}

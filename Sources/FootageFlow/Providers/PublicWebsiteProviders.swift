import Foundation

/// Direct-search providers intentionally parse only public, server-rendered result cards. They do
/// not solve challenges, read browser state, or fall back to authenticated endpoints.
struct DarefulProvider: MediaProvider {
  let loader: any DirectSearchPageLoading
  let info = ProviderInfo(
    id: .dareful, displayName: "Dareful", mode: .directSearch, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .bestEffort, preview: .bestEffort, metadata: .bestEffort,
      license: .supported, download: .bestEffort, supportsVideo: true, supportsImage: false,
      pagination: .bestEffort, accessMethods: [.directSearch, .externalTool]))

  init(loader: any DirectSearchPageLoading = LiveDirectSearchPageLoader()) {
    self.loader = loader
  }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard request.mediaType == .video || request.mediaType == .all else {
      return ProviderPage(assets: [], continuation: nil)
    }
    try await ProviderRequestLimiter.shared.wait(for: .dareful, minimumInterval: .milliseconds(750))
    let page = max(1, continuation?.page ?? 1)
    guard let url = DarefulHTMLParser.searchURL(query: request.query, page: page) else {
      throw ProviderError.invalidResponse
    }
    let html = try await loader.load(url, provider: .dareful)
    let assets = DarefulHTMLParser.assets(html: html, query: request.query, limit: request.pageSize)
    return ProviderPage(
      assets: assets,
      continuation: DarefulHTMLParser.hasNextPage(html) ? .nextPage(page + 1) : nil)
  }
}

struct ESAProvider: MediaProvider {
  let loader: any DirectSearchPageLoading
  let info = ProviderInfo(
    id: .esa, displayName: "ESA Multimedia", mode: .directSearch, requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .bestEffort, preview: .bestEffort, metadata: .bestEffort,
      license: .bestEffort, download: .unavailable, supportsVideo: true, supportsImage: true,
      pagination: .bestEffort, accessMethods: [.directSearch, .publicInterface]))

  init(loader: any DirectSearchPageLoading = LiveDirectSearchPageLoader()) {
    self.loader = loader
  }

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    guard request.mediaType != .audio else { return ProviderPage(assets: [], continuation: nil) }
    try await ProviderRequestLimiter.shared.wait(for: .esa, minimumInterval: .milliseconds(750))
    let page = max(1, continuation?.page ?? 1)
    guard let url = ESAHTMLParser.searchURL(query: request.query, page: page) else {
      throw ProviderError.invalidResponse
    }
    let html = try await loader.load(url, provider: .esa)
    let assets = ESAHTMLParser.assets(
      html: html, query: request.query, mediaType: request.mediaType, limit: request.pageSize)
    return ProviderPage(
      assets: assets,
      continuation: ESAHTMLParser.hasNextPage(html) ? .nextPage(page + 1) : nil)
  }
}

private enum DarefulHTMLParser {
  private static let licenseURL = URL(
    string: "https://dareful.com/about-dareful-completely-free-4k-stock-video/")!

  static func searchURL(query: String, page: Int) -> URL? {
    var components = URLComponents(string: "https://dareful.com/")
    components?.queryItems = [
      URLQueryItem(name: "s", value: query),
      URLQueryItem(name: "paged", value: page > 1 ? String(page) : nil),
    ].filter { $0.value != nil }
    guard let url = components?.url else { return nil }
    return try? URLValidator.remote(url)
  }

  static func assets(html: String, query: String, limit: Int) -> [MediaAsset] {
    WebsiteHTML.capture(#"(?is)<article\b([^>]*)>(.*?)</article>"#, in: html).enumerated()
      .compactMap {
        index, value in
        let attributes = value.0
        let body = value.1
        guard attributes.lowercased().contains("videoobject"),
          let rawID = WebsiteHTML.attribute("id", from: attributes)
            ?? WebsiteHTML.first(#"\bpost-(\d+)\b"#, in: attributes),
          let sourceText = WebsiteHTML.capture(#"(?is)<a\b([^>]*)>(.*?)</a>"#, in: body)
            .first(where: { $0.0.lowercased().contains("grid-link") })
            .flatMap({ WebsiteHTML.attribute("href", from: $0.0) }),
          let source = WebsiteHTML.remoteURL(
            sourceText, relativeTo: URL(string: "https://dareful.com/")),
          let title = WebsiteHTML.attribute("aria-label", from: attributes)
            ?? WebsiteHTML.first(
              #"(?is)itemprop=[\"']name[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body),
          let hlsText = WebsiteHTML.first(
            #"(?is)itemprop=[\"']contentURL[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body),
          let hls = WebsiteHTML.remoteURL(hlsText, relativeTo: source)
        else { return nil }
        let thumbnail = WebsiteHTML.first(
          #"(?is)itemprop=[\"']thumbnailUrl[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body
        )
        .flatMap { WebsiteHTML.remoteURL($0, relativeTo: source) }
        let description = WebsiteHTML.first(
          #"(?is)itemprop=[\"']description[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body)
        let duration = WebsiteHTML.isoDuration(
          WebsiteHTML.first(
            #"(?is)itemprop=[\"']duration[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body))
        let width = WebsiteHTML.integer(
          WebsiteHTML.first(
            #"(?is)itemprop=[\"']width[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body))
        let height = WebsiteHTML.integer(
          WebsiteHTML.first(
            #"(?is)itemprop=[\"']height[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body))
        let published = ProviderUtilities.parseDate(
          WebsiteHTML.first(
            #"(?is)itemprop=[\"']uploadDate[\"'][^>]*\bcontent=[\"']([^\"']+)[\"']"#, in: body))
        return MediaAsset(
          id: rawID, provider: .dareful, title: WebsiteHTML.text(title),
          description: description.map(WebsiteHTML.text), thumbnailURL: thumbnail, previewURL: hls,
          downloadURL: hls, sourcePageURL: source, creator: "Dareful", license: "CC BY 4.0",
          licenseURL: licenseURL, licenseStatus: .attributionRequired, width: width, height: height,
          duration: duration, fileType: "mp4", mediaType: .video, publishedDate: published,
          downloadable: true,
          originalMetadata: [
            "accessMode": ProviderMode.directSearch.rawValue,
            "sourceName": "Dareful",
            "ytDLPSourceURL": hls.absoluteString,
            "licenseSource": licenseURL.absoluteString,
          ], searchKeyword: query, relevanceScore: max(0.1, 0.88 - Double(index) * 0.02),
          downloadStrategy: .ytDLP,
          rightsInfo: RightsInfo(
            statement: "CC BY 4.0", uri: licenseURL, source: "Dareful", known: true,
            openLicense: true, attributionRequired: true, commercialUseKnown: true),
          downloadAvailability: .direct,
          thumbnailCandidates: thumbnail.map { [$0] })
      }
  }

  static func hasNextPage(_ html: String) -> Bool {
    html.range(
      of: #"(?is)<a\b[^>]*\bhref=[\"'][^\"']*(?:paged=|/page/)\d+[^\"']*[\"'][^>]*>\s*(?:Next|›)"#,
      options: .regularExpression) != nil
  }
}

private enum ESAHTMLParser {
  private static let termsURL = URL(
    string:
      "https://www.esa.int/ESA_Multimedia/Terms_and_conditions_of_use_of_images_and_videos_available_on_the_esa_website"
  )!

  static func searchURL(query: String, page: Int) -> URL? {
    var components = URLComponents(string: "https://www.esa.int/esearch")
    components?.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "start", value: page > 1 ? String((page - 1) * 10 + 1) : nil),
    ].filter { $0.value != nil }
    guard let url = components?.url else { return nil }
    return try? URLValidator.remote(url)
  }

  static func assets(html: String, query: String, mediaType: MediaType, limit: Int) -> [MediaAsset]
  {
    WebsiteHTML.captureTriple(
      #"(?is)<a\b[^>]*\bclass=[\"']card\s+([^\"']+)[\"'][^>]*\bhref=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#,
      in: html
    )
    .enumerated().compactMap { index, value in
      let classes = value.0.lowercased()
      let type: MediaType
      if classes.split(separator: " ").contains("video") {
        type = .video
      } else if classes.split(separator: " ").contains("image") {
        type = .image
      } else {
        return nil
      }
      guard mediaType == .all || mediaType == type,
        let source = WebsiteHTML.remoteURL(
          value.1, relativeTo: URL(string: "https://www.esa.int/")),
        let title = WebsiteHTML.first(#"(?is)<h3\b[^>]*>(.*?)</h3>"#, in: value.2)
      else { return nil }
      let thumbnail = WebsiteHTML.first(#"(?is)<img\b[^>]*\bsrc=[\"']([^\"']+)[\"']"#, in: value.2)
        .flatMap { WebsiteHTML.remoteURL($0, relativeTo: source) }
      return MediaAsset(
        id: source.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), provider: .esa,
        title: WebsiteHTML.text(title), description: nil, thumbnailURL: thumbnail,
        previewURL: type == .image ? thumbnail : nil, downloadURL: nil, sourcePageURL: source,
        creator: "European Space Agency", license: nil, licenseURL: termsURL,
        licenseStatus: .unknown, width: nil, height: nil, duration: nil,
        fileType: type == .image ? thumbnail?.pathExtension.lowercased() : nil, mediaType: type,
        publishedDate: nil, downloadable: false,
        originalMetadata: [
          "accessMode": ProviderMode.directSearch.rawValue,
          "sourceName": "ESA Multimedia",
          "discoveryOnly": "true",
          "rightsPolicyURL": termsURL.absoluteString,
        ], searchKeyword: query, relevanceScore: max(0.1, 0.78 - Double(index) * 0.02),
        downloadAvailability: .unavailable, thumbnailCandidates: thumbnail.map { [$0] })
    }.prefix(max(1, limit)).map { $0 }
  }

  static func hasNextPage(_ html: String) -> Bool {
    html.range(of: #"(?is)<a\b[^>]*\btitle=[\"']Next[\"']"#, options: .regularExpression) != nil
  }
}

private enum WebsiteHTML {
  static func capture(_ pattern: String, in value: String) -> [(String, String)] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
      guard $0.numberOfRanges > 2,
        let first = Range($0.range(at: 1), in: value),
        let second = Range($0.range(at: 2), in: value)
      else { return nil }
      return (String(value[first]), String(value[second]))
    }
  }

  static func captureTriple(_ pattern: String, in value: String) -> [(String, String, String)] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
      guard $0.numberOfRanges > 3,
        let first = Range($0.range(at: 1), in: value),
        let second = Range($0.range(at: 2), in: value),
        let third = Range($0.range(at: 3), in: value)
      else { return nil }
      return (String(value[first]), String(value[second]), String(value[third]))
    }
  }

  static func first(_ pattern: String, in value: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
      match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: value)
    else { return nil }
    return String(value[range])
  }

  static func attribute(_ name: String, from value: String) -> String? {
    first(
      "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']",
      in: value)
  }

  static func remoteURL(_ value: String, relativeTo base: URL?) -> URL? {
    let decoded = text(value)
    let normalized = decoded.hasPrefix("//") ? "https:\(decoded)" : decoded
    guard let url = URL(string: normalized, relativeTo: base)?.absoluteURL else { return nil }
    return try? URLValidator.remote(url)
  }

  static func text(_ value: String) -> String {
    ProviderUtilities.cleanHTML(value) ?? value
  }

  static func integer(_ value: String?) -> Int? { value.flatMap(Int.init) }

  static func isoDuration(_ value: String?) -> Double? {
    guard let value else { return nil }
    let pattern = #"(?i)^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    else { return Double(value) }
    func component(_ index: Int) -> Double {
      guard let range = Range(match.range(at: index), in: value) else { return 0 }
      return Double(value[range]) ?? 0
    }
    return component(1) * 3_600 + component(2) * 60 + component(3)
  }
}

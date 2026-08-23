import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shared, conservative throttle for public research services. This keeps the
/// public Crossref pool at one in-flight request and leaves the UI responsive
/// when a provider is temporarily unavailable.
private actor ResearchRequestLimiter {
  static let shared = ResearchRequestLimiter()
  private var lastRequest: [ResearchProviderID: Date] = [:]

  func wait(for provider: ResearchProviderID) async throws {
    let milliseconds: Int =
      switch provider {
      case .crossref: 1_000
      case .artInstituteChicago: 1_000
      // GDELT's public DOC endpoint requests a minimum five-second spacing.
      // Keep this conservative so a discovery query cannot make the rest of the
      // aggregated search look unavailable because of a 429 response.
      case .gdelt: 5_000
      default: 200
      }
    if let last = lastRequest[provider] {
      let remaining = Double(milliseconds) / 1_000 - Date().timeIntervalSince(last)
      if remaining > 0 { try await Task.sleep(for: .milliseconds(Int(remaining * 1_000))) }
    }
    lastRequest[provider] = .now
  }
}

/// Museum keyword searches can return very large object sets.  Detail
/// requests are intentionally bounded independently of the visible page size
/// so cancelling a search never leaves dozens of in-flight object fetches.
private actor ResearchDetailLimiter {
  private var permits: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(permits: Int) { self.permits = permits }

  func acquire() async {
    if permits > 0 {
      permits -= 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if let waiter = waiters.first {
      waiters.removeFirst()
      waiter.resume()
    } else {
      permits += 1
    }
  }
}

enum ResearchProviderFactory {
  static func make(_ id: ResearchProviderID) -> any ResearchProvider {
    switch id {
    case .wikipedia: WikipediaResearchProvider()
    case .wikidata: WikidataResearchProvider()
    case .metropolitanMuseum: MetropolitanMuseumResearchProvider()
    case .artInstituteChicago: ArtInstituteChicagoResearchProvider()
    case .crossref: CrossrefResearchProvider()
    case .gdelt: GDELTResearchProvider()
    }
  }
}

private enum ResearchProviderSupport {
  static func url(_ base: String, _ items: [URLQueryItem]) throws -> URL {
    try URL.endpoint(base, queryItems: items)
  }

  static func request(_ url: URL, userAgent: String? = nil) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
    return request
  }

  static func date(_ value: String?) -> Date? { ProviderUtilities.parseDate(value) }

  static func hints(title: String, metadata: [String: String], query: String) -> [String] {
    let candidates = [title, metadata["subject"], metadata["culture"], query]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    var seen = Set<String>()
    return candidates.filter { seen.insert($0.localizedLowercase).inserted }.prefix(4).map { $0 }
  }

  static func absoluteURL(_ string: String?, base: URL? = nil) -> URL? {
    guard let string, !string.isEmpty else { return nil }
    if string.hasPrefix("//") { return URLValidator.remote("https:\(string)") }
    if let url = URL(string: string), url.scheme != nil { return try? URLValidator.remote(url) }
    guard let resolved = base.flatMap({ URL(string: string, relativeTo: $0)?.absoluteURL }) else {
      return nil
    }
    return try? URLValidator.remote(resolved)
  }
}

struct WikipediaResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .wikipedia

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let language = request.interfaceLanguage.wikipediaLanguageCode
    let url = try ResearchProviderSupport.url(
      "https://\(language).wikipedia.org/w/rest.php/v1/search/page",
      [
        URLQueryItem(name: "q", value: request.query),
        URLQueryItem(name: "limit", value: String(min(request.pageSize, 20))),
        URLQueryItem(name: "offset", value: String(continuation?.offset ?? 0)),
      ])
    let response = try await HTTPClient.shared.decode(
      WikipediaSearchResponse.self, request: ResearchProviderSupport.request(url), maxRetries: 1)
    let base = URL(string: "https://\(language).wikipedia.org")!
    let qids = await wikipediaQIDs(for: response.pages.map(\.title), language: language)
    let records = response.pages.enumerated().compactMap { index, page -> ResearchRecord? in
      guard
        let source = ResearchProviderSupport.absoluteURL(
          "/wiki/\(page.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page.key)",
          base: base)
      else { return nil }
      let summary = ProviderUtilities.cleanHTML(page.excerpt ?? page.description)
      let thumbnail = ResearchProviderSupport.absoluteURL(page.thumbnail?.url, base: base)
      let qid = qids[page.title]
      let metadata = [
        "pageID": String(page.id), "description": page.description ?? "", "wikidataQID": qid ?? "",
      ]
      return ResearchRecord(
        id: "\(language)-\(page.id)", provider: id, type: .encyclopedia, title: page.title,
        source: "Wikipedia", sourceNativeID: String(page.id), canonicalURL: source,
        summary: summary,
        authors: [], publishedDate: nil, year: nil,
        language: request.interfaceLanguage, doi: nil, wikidataQID: qid, license: nil,
        licenseURL: nil,
        thumbnailURL: thumbnail, providerMetadata: metadata, searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.02,
        relatedMediaQueryHints: ResearchProviderSupport.hints(
          title: page.title, metadata: metadata, query: request.query))
    }
    let offset = continuation?.offset ?? 0
    let next =
      response.pages.count == min(request.pageSize, 20)
      ? ProviderContinuation(offset: offset + response.pages.count) : nil
    return ResearchProviderPage(records: records, continuation: next, totalResults: nil)
  }
}

private func wikipediaQIDs(for titles: [String], language: String) async -> [String: String] {
  guard !titles.isEmpty,
    let url = try? ResearchProviderSupport.url(
      "https://\(language).wikipedia.org/w/api.php",
      [
        URLQueryItem(name: "action", value: "query"),
        URLQueryItem(name: "prop", value: "pageprops"),
        URLQueryItem(name: "ppprop", value: "wikibase_item"),
        URLQueryItem(name: "titles", value: titles.joined(separator: "|")),
        URLQueryItem(name: "format", value: "json"),
      ])
  else { return [:] }
  guard
    let response = try? await HTTPClient.shared.decode(
      WikipediaQIDResponse.self, request: ResearchProviderSupport.request(url), maxRetries: 0)
  else { return [:] }
  return response.query.pages.values.reduce(into: [:]) { result, page in
    if let title = page.title, let qid = page.pageProps?.wikibaseItem { result[title] = qid }
  }
}

private struct WikipediaSearchResponse: Decodable { let pages: [WikipediaPage] }
private struct WikipediaPage: Decodable {
  let id: Int
  let key, title: String
  let excerpt, description: String?
  let thumbnail: WikipediaThumbnail?
}
private struct WikipediaThumbnail: Decodable { let url: String? }
private struct WikipediaQIDResponse: Decodable { let query: WikipediaQIDQuery }
private struct WikipediaQIDQuery: Decodable { let pages: [String: WikipediaQIDPage] }
private struct WikipediaQIDPage: Decodable {
  let title: String?
  let pageProps: WikipediaPageProps?
  enum CodingKeys: String, CodingKey {
    case title
    case pageProps = "pageprops"
  }
}
private struct WikipediaPageProps: Decodable {
  let wikibaseItem: String?
  enum CodingKeys: String, CodingKey { case wikibaseItem = "wikibase_item" }
}

struct WikidataResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .wikidata

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let offset = continuation?.offset ?? 0
    let url = try ResearchProviderSupport.url(
      "https://www.wikidata.org/w/api.php",
      [
        URLQueryItem(name: "action", value: "wbsearchentities"),
        URLQueryItem(name: "search", value: request.query),
        URLQueryItem(name: "language", value: request.interfaceLanguage.wikipediaLanguageCode),
        URLQueryItem(name: "uselang", value: request.interfaceLanguage.wikipediaLanguageCode),
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "limit", value: String(min(request.pageSize, 20))),
        URLQueryItem(name: "continue", value: String(offset)),
      ])
    let response = try await HTTPClient.shared.decode(
      WikidataSearchResponse.self, request: ResearchProviderSupport.request(url), maxRetries: 1)
    let records = response.search.enumerated().compactMap { index, entity -> ResearchRecord? in
      guard let source = URLValidator.remote("https://www.wikidata.org/wiki/\(entity.id)") else {
        return nil
      }
      let metadata = [
        "aliases": (entity.aliases ?? []).joined(separator: ", "),
        "entityType": entity.entityType ?? "",
      ]
      return ResearchRecord(
        id: entity.id, provider: id, type: .structuredData, title: entity.label,
        source: "Wikidata", sourceNativeID: entity.id, canonicalURL: source,
        summary: entity.description, authors: [], publishedDate: nil, year: nil,
        language: request.interfaceLanguage, doi: nil, wikidataQID: entity.id,
        license: nil, licenseURL: nil, thumbnailURL: nil, providerMetadata: metadata,
        searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.02,
        relatedMediaQueryHints: ResearchProviderSupport.hints(
          title: entity.label, metadata: metadata, query: request.query))
    }
    let next =
      response.search.count == min(request.pageSize, 20)
      ? ProviderContinuation(offset: offset + response.search.count) : nil
    return ResearchProviderPage(records: records, continuation: next, totalResults: nil)
  }
}

private struct WikidataSearchResponse: Decodable { let search: [WikidataEntity] }
private struct WikidataEntity: Decodable {
  let id, label: String
  let description: String?
  let aliases: [String]?
  let entityType: String?
  enum CodingKeys: String, CodingKey {
    case id, label, description, aliases
    case entityType = "entitytype"
  }
}

struct MetropolitanMuseumResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .metropolitanMuseum

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let page = max(1, continuation?.page ?? 1)
    let idsURL = try ResearchProviderSupport.url(
      "https://collectionapi.metmuseum.org/public/collection/v1/search",
      [URLQueryItem(name: "q", value: request.query)])
    let search = try await HTTPClient.shared.decode(
      MetSearchResponse.self, request: ResearchProviderSupport.request(idsURL), maxRetries: 1)
    let pageSize = min(request.pageSize, 12)
    let start = (page - 1) * pageSize
    guard start < search.objectIDs.count else {
      return ResearchProviderPage(records: [], continuation: nil, totalResults: search.total)
    }
    let objectIDs = Array(search.objectIDs.dropFirst(start).prefix(pageSize))
    let records = await details(objectIDs, request: request)
    let next =
      start + objectIDs.count < search.objectIDs.count
      ? ProviderContinuation.nextPage(page + 1) : nil
    return ResearchProviderPage(records: records, continuation: next, totalResults: search.total)
  }

  private func details(_ ids: [Int], request: ResearchSearchRequest) async -> [ResearchRecord] {
    await withTaskGroup(of: ResearchRecord?.self, returning: [ResearchRecord].self) { group in
      let limiter = ResearchDetailLimiter(permits: 4)
      for (index, objectID) in ids.enumerated() {
        group.addTask {
          await limiter.acquire()
          defer { Task { await limiter.release() } }
          guard
            let url = URL(
              string: "https://collectionapi.metmuseum.org/public/collection/v1/objects/\(objectID)"
            )
          else { return nil }
          guard
            let object = try? await HTTPClient.shared.decode(
              MetObject.self, request: ResearchProviderSupport.request(url), maxRetries: 1),
            let source = ResearchProviderSupport.absoluteURL(object.objectURL)
          else { return nil }
          let creators = [object.artistDisplayName, object.culture].compactMap { $0?.nilIfEmpty }
          let rights = object.isPublicDomain == true ? "Public Domain" : nil
          let metadata = [
            "department": object.department ?? "", "culture": object.culture ?? "",
            "period": object.period ?? "",
            "medium": object.medium ?? "", "creditLine": object.creditLine ?? "",
            "publicDomain": object.isPublicDomain == true ? "true" : "false",
            "publicImageURL": object.primaryImage ?? "",
          ]
          return ResearchRecord(
            id: "met-\(object.objectID)", provider: .metropolitanMuseum, type: .culturalCollection,
            title: object.title.nilIfEmpty ?? "The Met object \(object.objectID)",
            source: "The Metropolitan Museum of Art",
            sourceNativeID: String(object.objectID), canonicalURL: source,
            summary: [object.objectName, object.medium, object.objectDate].compactMap {
              $0?.nilIfEmpty
            }.joined(separator: " · ").nilIfEmpty,
            authors: creators, publishedDate: nil, year: object.objectDate, language: nil, doi: nil,
            wikidataQID: nil,
            license: rights, licenseURL: nil,
            thumbnailURL: ResearchProviderSupport.absoluteURL(object.primaryImageSmall),
            providerMetadata: metadata, searchKeyword: request.query,
            relevanceScore: 1 - Double(index) * 0.02,
            relatedMediaQueryHints: ResearchProviderSupport.hints(
              title: object.title, metadata: metadata, query: request.query))
        }
      }
      var values: [ResearchRecord] = []
      for await record in group { if let record { values.append(record) } }
      return values.sorted { $0.relevanceScore > $1.relevanceScore }
    }
  }
}

private struct MetSearchResponse: Decodable {
  let total: Int
  let objectIDs: [Int]
  enum CodingKeys: String, CodingKey {
    case total
    case objectIDs = "objectIDs"
  }
}
private struct MetObject: Decodable {
  let objectID: Int
  let title: String
  let artistDisplayName, culture, period, medium, department, creditLine, objectDate,
    objectName: String?
  let objectURL, primaryImageSmall, primaryImage: String?
  let isPublicDomain: Bool?
}

struct ArtInstituteChicagoResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .artInstituteChicago

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let page = max(1, continuation?.page ?? 1)
    let fields =
      "id,title,artist_display,date_display,department_title,place_of_origin,medium_display,credit_line,image_id,is_public_domain,web_url,api_link"
    let url = try ResearchProviderSupport.url(
      "https://api.artic.edu/api/v1/artworks/search",
      [
        URLQueryItem(name: "q", value: request.query),
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "limit", value: String(min(request.pageSize, 20))),
        URLQueryItem(name: "fields", value: fields),
      ])
    let response = try await HTTPClient.shared.decode(
      AICSearchResponse.self,
      request: ResearchProviderSupport.request(
        url,
        userAgent:
          "FootageFlow/\(FootageFlowVersion.current) (https://github.com/xcslys99/FootageFlow)"),
      maxRetries: 1)
    let baseIIIF = response.config?.iiifURL
    let records = response.data.enumerated().compactMap { index, artwork -> ResearchRecord? in
      // The search API currently exposes an api_link, but not a stable
      // public web_url in its selected fields.  Present the real artwork page,
      // not the JSON endpoint, as the record's source page.
      guard let source = URLValidator.remote("https://www.artic.edu/artworks/\(artwork.id)") else {
        return nil
      }
      let thumbnail = artwork.imageID.flatMap { imageID in
        baseIIIF.flatMap {
          ResearchProviderSupport.absoluteURL("\($0)/\(imageID)/full/843,/0/default.jpg")
        }
      }
      let metadata = [
        "department": artwork.departmentTitle ?? "", "origin": artwork.placeOfOrigin ?? "",
        "medium": artwork.mediumDisplay ?? "", "creditLine": artwork.creditLine ?? "",
        "publicDomain": artwork.isPublicDomain == true ? "true" : "false",
        "publicImageURL": artwork.isPublicDomain == true ? thumbnail?.absoluteString ?? "" : "",
      ]
      return ResearchRecord(
        id: "aic-\(artwork.id)", provider: id, type: .culturalCollection, title: artwork.title,
        source: "Art Institute of Chicago", sourceNativeID: String(artwork.id),
        canonicalURL: source,
        summary: [artwork.mediumDisplay, artwork.departmentTitle].compactMap { $0?.nilIfEmpty }
          .joined(separator: " · ").nilIfEmpty,
        authors: artwork.artistDisplay.map { [$0] } ?? [], publishedDate: nil,
        year: artwork.dateDisplay,
        language: nil, doi: nil, wikidataQID: nil,
        license: artwork.isPublicDomain == true ? "Public Domain" : nil, licenseURL: nil,
        thumbnailURL: thumbnail, providerMetadata: metadata, searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.02,
        relatedMediaQueryHints: ResearchProviderSupport.hints(
          title: artwork.title, metadata: metadata, query: request.query))
    }
    let hasMore = response.pagination?.currentPage ?? page < response.pagination?.totalPages ?? page
    return ResearchProviderPage(
      records: records, continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: response.pagination?.total)
  }
}

private struct AICSearchResponse: Decodable {
  let data: [AICArtwork]
  let pagination: AICPagination?
  let config: AICConfig?
}
private struct AICPagination: Decodable {
  let total, totalPages, currentPage: Int?
  enum CodingKeys: String, CodingKey {
    case total
    case totalPages = "total_pages"
    case currentPage = "current_page"
  }
}
private struct AICConfig: Decodable {
  let iiifURL: String?
  enum CodingKeys: String, CodingKey { case iiifURL = "iiif_url" }
}
private struct AICArtwork: Decodable {
  let id: Int
  let title: String
  let artistDisplay, dateDisplay, departmentTitle, placeOfOrigin, mediumDisplay, creditLine,
    imageID, webURL, apiLink: String?
  let isPublicDomain: Bool?
  enum CodingKeys: String, CodingKey {
    case id, title, creditLine, apiLink
    case artistDisplay = "artist_display"
    case dateDisplay = "date_display"
    case departmentTitle = "department_title"
    case placeOfOrigin = "place_of_origin"
    case mediumDisplay = "medium_display"
    case imageID = "image_id"
    case webURL = "web_url"
    case isPublicDomain = "is_public_domain"
  }
}

struct CrossrefResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .crossref

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let offset = continuation?.offset ?? 0
    let url = try ResearchProviderSupport.url(
      "https://api.crossref.org/works",
      [
        URLQueryItem(name: "query.bibliographic", value: request.query),
        URLQueryItem(name: "rows", value: String(min(request.pageSize, 20))),
        URLQueryItem(name: "offset", value: String(offset)),
        URLQueryItem(
          name: "select",
          value: "DOI,title,author,issued,container-title,publisher,abstract,URL,license,type"),
      ])
    let response = try await HTTPClient.shared.decode(
      CrossrefResponse.self,
      request: ResearchProviderSupport.request(
        url,
        userAgent:
          "FootageFlow/\(FootageFlowVersion.current) (https://github.com/xcslys99/FootageFlow)"),
      maxRetries: 1)
    let records = response.message.items.enumerated().compactMap { index, item -> ResearchRecord? in
      let doiURL = item.doi.flatMap { URLValidator.remote("https://doi.org/\($0)") }
      guard let source = doiURL ?? ResearchProviderSupport.absoluteURL(item.url) else { return nil }
      let authors = (item.author ?? []).compactMap { author in
        [author.given, author.family].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
          .nilIfEmpty
      }
      // Crossref may legitimately return a partial or unknown date as
      // `[[null]]`. Treat that as absent metadata rather than rejecting the
      // entire valid response during decoding.
      let year = item.issued?.dateParts?.first?.compactMap { $0 }.first.map(String.init)
      let licenseURL = ResearchProviderSupport.absoluteURL(item.license?.first?.url)
      let metadata = [
        "containerTitle": item.containerTitle?.first ?? "", "publisher": item.publisher ?? "",
        "workType": item.type ?? "",
      ]
      return ResearchRecord(
        id: item.doi ?? source.absoluteString, provider: id, type: .academic,
        title: item.title?.first?.nilIfEmpty ?? item.doi ?? "Crossref work", source: "Crossref",
        sourceNativeID: item.doi, canonicalURL: source,
        summary: ProviderUtilities.cleanHTML(item.abstract),
        authors: authors, publishedDate: year.flatMap(ProviderUtilities.parseDate), year: year,
        language: nil, doi: item.doi, wikidataQID: nil,
        license: licenseURL == nil ? nil : "License provided by Crossref metadata",
        licenseURL: licenseURL, thumbnailURL: nil, providerMetadata: metadata,
        searchKeyword: request.query,
        relevanceScore: 1 - Double(index) * 0.02,
        relatedMediaQueryHints: ResearchProviderSupport.hints(
          title: item.title?.first ?? request.query, metadata: metadata, query: request.query))
    }
    let next =
      records.count == min(request.pageSize, 20)
      ? ProviderContinuation(offset: offset + records.count) : nil
    return ResearchProviderPage(
      records: records, continuation: next, totalResults: response.message.totalResults)
  }
}

private struct CrossrefResponse: Decodable { let message: CrossrefMessage }
private struct CrossrefMessage: Decodable {
  let totalResults: Int?
  let items: [CrossrefWork]
  enum CodingKeys: String, CodingKey {
    case totalResults = "total-results"
    case items
  }
}
private struct CrossrefWork: Decodable {
  let doi: String?
  let title, containerTitle: [String]?
  let author: [CrossrefAuthor]?
  let issued: CrossrefIssued?
  let publisher, abstract, url, type: String?
  let license: [CrossrefLicense]?
  enum CodingKeys: String, CodingKey {
    case title, author, issued, publisher, abstract, url, type, license
    case doi = "DOI"
    case containerTitle = "container-title"
  }
}
private struct CrossrefAuthor: Decodable { let given, family: String? }
private struct CrossrefIssued: Decodable {
  let dateParts: [[Int?]]?
  enum CodingKeys: String, CodingKey { case dateParts = "date-parts" }
}
private struct CrossrefLicense: Decodable { let url: String? }

struct GDELTResearchProvider: ResearchProvider {
  let id: ResearchProviderID = .gdelt

  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
  {
    try await ResearchRequestLimiter.shared.wait(for: id)
    let url = try ResearchProviderSupport.url(
      "https://api.gdeltproject.org/api/v2/doc/doc",
      [
        URLQueryItem(name: "query", value: request.query),
        URLQueryItem(name: "mode", value: "artlist"),
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "maxrecords", value: String(min(request.pageSize, 25))),
      ])
    let response = try await HTTPClient.shared.decode(
      GDELTResponse.self, request: ResearchProviderSupport.request(url), maxRetries: 1)
    let records = response.articles.enumerated().compactMap { index, article -> ResearchRecord? in
      guard let source = ResearchProviderSupport.absoluteURL(article.url) else { return nil }
      let metadata = [
        "publisher": article.domain ?? "", "sourceCountry": article.sourceCountry ?? "",
      ]
      return ResearchRecord(
        id: article.url, provider: id, type: .news, title: article.title ?? article.url,
        source: article.domain ?? "GDELT", sourceNativeID: article.url, canonicalURL: source,
        summary: article.seendate, authors: [],
        publishedDate: ResearchProviderSupport.date(article.seendate),
        year: article.seendate.flatMap { String($0.prefix(4)) },
        language: article.language.flatMap(AppLanguage.init(rawValue:)),
        doi: nil, wikidataQID: nil, license: nil, licenseURL: nil,
        thumbnailURL: ResearchProviderSupport.absoluteURL(article.socialImage),
        providerMetadata: metadata,
        searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.02,
        relatedMediaQueryHints: ResearchProviderSupport.hints(
          title: article.title ?? request.query, metadata: metadata, query: request.query))
    }
    return ResearchProviderPage(records: records, continuation: nil, totalResults: records.count)
  }
}

private struct GDELTResponse: Decodable { let articles: [GDELTArticle] }
private struct GDELTArticle: Decodable {
  let url: String
  let title, seendate, domain, language, socialImage, sourceCountry: String?
  enum CodingKeys: String, CodingKey {
    case url, title, seendate, domain, language
    case socialImage = "socialimage"
    case sourceCountry = "sourcecountry"
  }
}

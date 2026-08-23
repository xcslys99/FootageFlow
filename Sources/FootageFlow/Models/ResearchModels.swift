import Foundation

/// The top-level search scope. Media remains the default so existing creator
/// workflows behave exactly as they did before the research update.
enum SearchScope: String, Codable, CaseIterable, Identifiable, Sendable {
  case media, research, all

  var id: String { rawValue }
  var label: String {
    switch self {
    case .media: tr("search.scope.media")
    case .research: tr("search.scope.research")
    case .all: tr("search.scope.all")
    }
  }
}

enum ResearchProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
  case wikipedia, wikidata, metropolitanMuseum, artInstituteChicago, crossref, gdelt

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .wikipedia: "Wikipedia"
    case .wikidata: "Wikidata"
    case .metropolitanMuseum: "The Metropolitan Museum of Art"
    case .artInstituteChicago: "Art Institute of Chicago"
    case .crossref: "Crossref"
    case .gdelt: "GDELT"
    }
  }
}

enum ResearchRecordType: String, Codable, CaseIterable, Identifiable, Sendable {
  case encyclopedia, structuredData, academic, news, culturalCollection

  var id: String { rawValue }
  var label: String {
    switch self {
    case .encyclopedia: tr("research.type.encyclopedia")
    case .structuredData: tr("research.type.structuredData")
    case .academic: tr("research.type.academic")
    case .news: tr("research.type.news")
    case .culturalCollection: tr("research.type.culturalCollection")
    }
  }
}

struct ResearchRecord: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var provider: ResearchProviderID
  var type: ResearchRecordType
  var title: String
  var source: String
  var sourceNativeID: String?
  var canonicalURL: URL
  var summary: String?
  var authors: [String]
  var publishedDate: Date?
  var year: String?
  var language: AppLanguage?
  var doi: String?
  var wikidataQID: String?
  var license: String?
  var licenseURL: URL?
  var thumbnailURL: URL?
  var providerMetadata: [String: String]
  var searchKeyword: String
  var relevanceScore: Double
  var relatedMediaQueryHints: [String]
  var createdAt: Date = .now

  var stableID: String { "\(provider.rawValue):\(sourceNativeID ?? id)" }
  var displayAuthors: String { authors.filter { !$0.isEmpty }.joined(separator: ", ") }
  var citationText: String { ResearchCitationFormatter.citation(for: self) }
  var isDiscoveryOnly: Bool { provider == .gdelt || provider == .crossref }
}

/// Converts only an explicitly public-domain cultural record with a real public
/// image into a normal FootageFlow media asset. Research records are never
/// assumed downloadable simply because they have a thumbnail or source page.
enum ResearchMediaAdapter {
  static func asset(for record: ResearchRecord) -> MediaAsset? {
    guard
      [.metropolitanMuseum, .artInstituteChicago].contains(record.provider),
      record.providerMetadata["publicDomain"] == "true",
      let imageURL = URLValidator.remote(record.providerMetadata["publicImageURL"])
    else { return nil }

    return MediaAsset(
      id: "research-\(record.stableID)", provider: .wikimedia,
      title: record.title, description: record.summary,
      thumbnailURL: record.thumbnailURL ?? imageURL, previewURL: imageURL, downloadURL: imageURL,
      sourcePageURL: record.canonicalURL, creator: record.displayAuthors.nilIfEmpty,
      license: record.license ?? "Public Domain", licenseURL: record.licenseURL,
      licenseStatus: .publicDomain, width: nil, height: nil, duration: nil,
      fileType: imageURL.pathExtension.nilIfEmpty ?? "image", mediaType: .image,
      publishedDate: record.publishedDate, downloadable: true,
      originalMetadata: record.providerMetadata.merging(
        [
          "sourceName": record.source,
          "researchProvider": record.provider.rawValue,
          "researchRecordID": record.id,
        ], uniquingKeysWith: { _, new in new }),
      searchKeyword: record.searchKeyword, relevanceScore: record.relevanceScore,
      downloadStrategy: .directURL,
      rightsInfo: RightsInfo(
        statement: record.license ?? "Public Domain", uri: record.licenseURL,
        source: record.source, known: true, publicDomain: true, openLicense: true),
      downloadAvailability: .direct,
      thumbnailCandidates: [record.thumbnailURL, imageURL].compactMap { $0 })
  }
}

struct ResearchProviderPage: Sendable {
  var records: [ResearchRecord]
  var continuation: ProviderContinuation?
  var totalResults: Int?
}

protocol ResearchProvider: Sendable {
  var id: ResearchProviderID { get }
  func search(_ request: ResearchSearchRequest, continuation: ProviderContinuation?) async throws
    -> ResearchProviderPage
}

struct ResearchSearchRequest: Sendable {
  var query: String
  var interfaceLanguage: AppLanguage
  var pageSize: Int = 12
}

struct ResearchProviderResult: Sendable {
  var provider: ResearchProviderID
  var records: [ResearchRecord]
  var error: ProviderError?
  var continuation: ProviderContinuation?
  var totalResults: Int?
}

/// Local-only filters for research records.  They never infer missing dates or
/// source facts: records without a real year simply remain visible unless a
/// user explicitly asks for a year range.
struct ResearchSearchFilter: Sendable {
  var types: Set<ResearchRecordType> = Set(ResearchRecordType.allCases)
  var providers: Set<ResearchProviderID> = Set(ResearchProviderID.allCases)
  var yearFrom: Int?
  var yearTo: Int?

  func matches(_ record: ResearchRecord) -> Bool {
    guard types.contains(record.type), providers.contains(record.provider) else { return false }
    guard yearFrom != nil || yearTo != nil else { return true }
    guard let numericYear = record.year?.prefix(4), let year = Int(numericYear) else {
      return false
    }
    if let yearFrom, year < yearFrom { return false }
    if let yearTo, year > yearTo { return false }
    return true
  }
}

/// Refreshes one saved reference by asking only its original public provider.
/// It intentionally preserves the user's note, tags, and added timestamp; a
/// failed request returns the existing value so offline use cannot lose data.
enum ResearchMetadataRefresher {
  static func refresh(
    _ reference: ResearchReferenceRecord, interfaceLanguage: AppLanguage
  ) async throws -> ResearchReferenceRecord {
    let record = reference.record
    let query = record.sourceNativeID?.nilIfEmpty ?? record.wikidataQID?.nilIfEmpty ?? record.title
    let page = try await ResearchProviderFactory.make(record.provider).search(
      ResearchSearchRequest(query: query, interfaceLanguage: interfaceLanguage, pageSize: 12),
      continuation: nil)
    guard
      let refreshed = page.records.first(where: { $0.stableID == record.stableID })
        ?? page.records.first(where: { $0.canonicalURL == record.canonicalURL })
    else {
      throw ProviderError.message("The source record is no longer available.")
    }
    var value = reference
    value.record = refreshed
    value.updatedAt = .now
    return value
  }
}

/// A project-scoped local-first research note. Provider data stays inside the
/// immutable `record`; only `myNote` and `tags` are user editable.
struct ResearchReferenceRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var projectID: UUID
  var record: ResearchRecord
  var myNote: String = ""
  var tags: [String] = []
  var addedAt: Date = .now
  var updatedAt: Date = .now

  var stableID: String { record.stableID }
}

enum ResearchCitationFormatter {
  static func citation(for record: ResearchRecord) -> String {
    let title = safe(record.title)
    let url = record.canonicalURL.absoluteString
    switch record.provider {
    case .wikipedia:
      let language = record.language?.displayName ?? "Wikipedia"
      return "\(title). \(language) Wikipedia. \(url)"
    case .wikidata:
      let qid = record.wikidataQID ?? record.sourceNativeID ?? ""
      return [title, "Wikidata", qid, url].filter { !$0.isEmpty }.joined(separator: ". ")
    case .crossref:
      let authors = record.displayAuthors
      let year = record.year ?? ""
      let container = record.providerMetadata["containerTitle"] ?? ""
      let doi = record.doi.map { "https://doi.org/\($0)" } ?? url
      return [authors, year, title, container, doi].filter { !$0.isEmpty }.joined(separator: ". ")
    case .gdelt:
      let publisher = record.providerMetadata["publisher"] ?? record.source
      let date = record.year ?? ""
      return [title, publisher, date, url].filter { !$0.isEmpty }.joined(separator: ". ")
    case .metropolitanMuseum, .artInstituteChicago:
      let creator = record.displayAuthors
      let date = record.year ?? ""
      return [title, creator, record.source, date, url].filter { !$0.isEmpty }.joined(
        separator: ". ")
    }
  }

  private static func safe(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Research requests remain deliberately small: one user-language query plus
/// an English fallback is enough for public research APIs, and avoids turning a
/// single search into hundreds of network requests.
enum ResearchQueryPlanner {
  static func queries(for query: String, interfaceLanguage: AppLanguage) -> [SearchKeyword] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    let inputLanguage = MultilingualQueryEngine.detectLanguage(
      in: clean, fallback: interfaceLanguage)
    var values = [
      SearchKeyword(text: clean, language: inputLanguage, origin: .input, priority: 0)
    ]
    let plan = MultilingualQueryEngine.plan(
      for: clean, interfaceLanguage: interfaceLanguage, includeVisualExpansions: false)
    if let english = plan.keywords.first(where: { $0.language == .english && $0.text != clean }) {
      values.append(
        SearchKeyword(
          text: english.text, language: .english, origin: .multilingualCanonical, priority: 1))
    }
    var seen = Set<String>()
    return values.filter {
      seen.insert(
        $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      ).inserted
    }
  }
}

extension AppLanguage {
  var wikipediaLanguageCode: String {
    switch self {
    case .english: "en"
    case .simplifiedChinese, .traditionalChinese: "zh"
    case .spanish: "es"
    case .brazilianPortuguese: "pt"
    case .japanese: "ja"
    case .korean: "ko"
    case .german: "de"
    case .french: "fr"
    case .russian: "ru"
    }
  }
}

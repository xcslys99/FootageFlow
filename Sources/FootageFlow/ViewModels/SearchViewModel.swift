import Foundation

private actor SearchRequestLimiter {
  static let shared = SearchRequestLimiter(limit: 12)
  private let limit: Int
  private var active = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) { self.limit = limit }

  func acquire() async {
    if active < limit {
      active += 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty { active = max(0, active - 1) } else { waiters.removeFirst().resume() }
  }
}

private struct ProviderQueryOutcome: Sendable {
  let index: Int
  let keyword: SearchKeyword
  let page: ProviderPage?
  let error: Error?
}

@MainActor
final class SearchViewModel: ObservableObject {
  @Published var query = ""
  @Published var searchScope: SearchScope = .media
  @Published var keywords: [SearchKeyword] = []
  @Published var mediaType: MediaType = .video
  @Published var orientation: AssetOrientation = .all
  @Published var resolution: ResolutionFilter = .all
  @Published var duration: DurationFilter = .all
  @Published var licenseFilter: LicenseFilter = .all
  @Published var yearFrom: Int?
  @Published var yearTo: Int?
  @Published var downloadableOnly = false
  @Published var smartExpansionEnabled = AppSettings.smartExpansionEnabled {
    didSet { AppSettings.smartExpansionEnabled = smartExpansionEnabled }
  }
  @Published var relevanceMode = AppSettings.searchRelevanceMode {
    didSet {
      AppSettings.searchRelevanceMode = relevanceMode
      rerankAssets()
    }
  }
  @Published var sort: SearchSort = .relevance
  @Published var selectedProviders = AppSettings.enabledProviders
  @Published var currentProjectID: UUID?
  @Published var selectedResearchTypes = Set(ResearchRecordType.allCases)
  @Published var selectedResearchProviders = Set(ResearchProviderID.allCases)
  @Published var researchYearFrom: Int?
  @Published var researchYearTo: Int?
  @Published private(set) var assets: [MediaAsset] = []
  @Published private(set) var researchRecords: [ResearchRecord] = []
  @Published private(set) var providerErrors: [ProviderID: ProviderError] = [:]
  @Published private(set) var researchProviderErrors: [ResearchProviderID: ProviderError] = [:]
  @Published private(set) var providerCounts: [ProviderID: Int] = [:]
  @Published private(set) var researchProviderCounts: [ResearchProviderID: Int] = [:]
  @Published private(set) var providerStates: [ProviderID: ProviderRuntimeState] = [:]
  @Published private(set) var providerModes: [ProviderID: ProviderMode] = [:]
  @Published private(set) var isSearching = false
  @Published private(set) var isResearchSearching = false
  @Published private(set) var isLoadingMoreResearch = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var loadMoreFailedProviders = Set<ProviderID>()
  @Published private(set) var status: SearchStatus = .initial

  private var task: Task<Void, Never>?
  private var researchTask: Task<Void, Never>?
  private var store: DataStore?
  private var candidateAssets: [MediaAsset] = []
  private var relevanceQueries: [String] = []
  private var searchInputLanguage: AppLanguage = .english
  private var searchInterfaceLanguage: AppLanguage = .english
  private var pagination: [ProviderID: [ProviderQueryPageState]] = [:]
  private var researchPagination: [ResearchProviderID: ProviderContinuation] = [:]
  private var researchRequests: [ResearchProviderID: ResearchSearchRequest] = [:]
  private var loadMoreInFlight: [ProviderID: ProviderQueryPageState] = [:]
  private var searchGeneration = UUID()
  private var requestedMediaType: MediaType?

  var statusText: String { status.text }
  var isAnySearching: Bool { isSearching || isResearchSearching }
  var canLoadMore: Bool { !pagination.values.allSatisfy(\.isEmpty) }
  var canLoadMoreResearch: Bool { !researchPagination.isEmpty }
  var providersWithMoreResults: Set<ProviderID> {
    Set(pagination.compactMap { $0.value.isEmpty ? nil : $0.key })
  }

  var filteredAssets: [MediaAsset] {
    let filter = AdvancedSearchFilter(
      mediaType: mediaType, orientation: orientation, resolution: resolution,
      duration: duration, license: licenseFilter, selectedProviders: selectedProviders,
      yearFrom: yearFrom, yearTo: yearTo, downloadableOnly: downloadableOnly)
    var value = assets.filter { filter.matches($0) }
    switch sort {
    case .relevance: value.sort { score($0) > score($1) }
    case .newest:
      value.sort { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    case .resolution:
      value.sort {
        let left = ($0.width ?? 0) * ($0.height ?? 0)
        let right = ($1.width ?? 0) * ($1.height ?? 0)
        return left > right
      }
    case .duration: value.sort { ($0.duration ?? -1) > ($1.duration ?? -1) }
    }
    return value
  }

  var filteredResearchRecords: [ResearchRecord] {
    let filter = ResearchSearchFilter(
      types: selectedResearchTypes, providers: selectedResearchProviders,
      yearFrom: researchYearFrom, yearTo: researchYearTo)
    return researchRecords.filter(filter.matches)
  }

  func configure(store: DataStore) { self.store = store }

  func refreshProviderConfiguration() {
    let providers = makeProviders(directOverrides: [])
    for id in ProviderID.searchCases {
      guard selectedProviders.contains(id),
        let provider = providers.first(where: { $0.info.id == id })
      else {
        providerModes[id] = nil
        providerStates[id] = ProviderRuntimeState(availability: .disabled, message: nil)
        continue
      }
      setInitialState(for: provider)
    }
  }

  @discardableResult
  func prepareKeywords(
    translated: String? = nil, interfaceLanguage: AppLanguage = .english
  ) -> MultilingualQueryPlan {
    let plan = MultilingualQueryEngine.plan(
      for: query, interfaceLanguage: interfaceLanguage, translatedSupplement: translated,
      includeVisualExpansions: smartExpansionEnabled)
    keywords = plan.keywords
    searchInputLanguage = plan.inputLanguage
    searchInterfaceLanguage = plan.interfaceLanguage
    return plan
  }
  func acceptTranslation(_ text: String) {
    keywords = KeywordEngine.mergeTranslation(text, into: keywords)
  }
  func restoreKeywords(_ restored: [SearchKeyword], interfaceLanguage: AppLanguage) {
    keywords = restored
    searchInterfaceLanguage = interfaceLanguage
    searchInputLanguage =
      restored.first(where: { $0.origin == .input })?.language
      ?? MultilingualQueryEngine.detectLanguage(in: query, fallback: interfaceLanguage)
  }
  func addKeyword() {
    keywords.append(
      SearchKeyword(
        text: "", language: searchInterfaceLanguage, origin: .userAdded, priority: 99))
  }
  func removeKeyword(_ id: UUID) { keywords.removeAll { $0.id == id } }

  /// Restores visible filters without discarding the query, its keyword plan,
  /// project selection, or loaded results.
  func clearFilters() {
    let shouldRefreshMedia = MediaSearchRefreshPolicy.requiresNewSearch(
      previousRequest: requestedMediaType, selected: .video,
      scope: searchScope, query: query)
    mediaType = .video
    orientation = .all
    resolution = .all
    duration = .all
    licenseFilter = .all
    yearFrom = nil
    yearTo = nil
    downloadableOnly = false
    relevanceMode = .balanced
    sort = .relevance
    selectedProviders = AppSettings.enabledProviders
    selectedResearchTypes = Set(ResearchRecordType.allCases)
    selectedResearchProviders = Set(ResearchProviderID.allCases)
    researchYearFrom = nil
    researchYearTo = nil
    if shouldRefreshMedia { search() }
  }

  /// A media-type picker changes what providers are asked to return, not just
  /// which already-loaded cards are visible. Refresh the provider search after
  /// a submitted query so switching Video ↔ Image cannot show a false empty state.
  func selectMediaType(_ value: MediaType) {
    guard mediaType != value else { return }
    mediaType = value
    if MediaSearchRefreshPolicy.requiresNewSearch(
      previousRequest: requestedMediaType, selected: value,
      scope: searchScope, query: query)
    {
      search()
    }
  }

  func savedSearch(named name: String) -> SavedSearchRecord {
    SavedSearchRecord(
      name: name, query: query, keywords: keywords, searchScope: searchScope, mediaType: mediaType,
      orientation: orientation, resolution: resolution, duration: duration,
      licenseFilter: licenseFilter,
      yearFrom: yearFrom, yearTo: yearTo, downloadableOnly: downloadableOnly,
      relevanceMode: relevanceMode, providerIDs: selectedProviders.map(\.rawValue).sorted())
  }

  func apply(savedSearch: SavedSearchRecord) {
    query = savedSearch.query
    keywords = savedSearch.keywords
    searchScope = savedSearch.searchScope
    mediaType = savedSearch.mediaType
    orientation = savedSearch.orientation
    resolution = savedSearch.resolution
    duration = savedSearch.duration
    licenseFilter = savedSearch.licenseFilter
    yearFrom = savedSearch.yearFrom
    yearTo = savedSearch.yearTo
    downloadableOnly = savedSearch.downloadableOnly
    relevanceMode = savedSearch.relevanceMode
    selectedProviders =
      savedSearch.providerSet.isEmpty ? Set(ProviderID.searchCases) : savedSearch.providerSet
    if keywords.isEmpty { _ = prepareKeywords() }
  }

  /// Clears only the transient search state. Project records, favorites,
  /// history and saved searches remain untouched.
  func clearSearch() {
    stop()
    query = ""
    keywords = []
    assets = []
    researchRecords = []
    candidateAssets = []
    providerErrors = [:]
    researchProviderErrors = [:]
    providerCounts = [:]
    researchProviderCounts = [:]
    pagination = [:]
    researchPagination = [:]
    researchRequests = [:]
    status = .initial
    requestedMediaType = nil
  }

  func search(
    forceRefresh: Bool = false, only providerID: ProviderID? = nil,
    directOverrides: Set<ProviderID> = []
  ) {
    let activeKeywords = keywords.filter {
      $0.isEnabled && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
    }
    let active = activeKeywords.map(\.text)
    relevanceQueries = active
    guard !active.isEmpty else {
      prepareKeywords()
      if keywords.isEmpty {
        status = .enterQuery
        return
      }
      search(
        forceRefresh: forceRefresh, only: providerID, directOverrides: directOverrides)
      return
    }
    task?.cancel()
    researchTask?.cancel()
    let generation = UUID()
    searchGeneration = generation
    if searchScope != .media {
      startResearchSearch(active: active, generation: generation)
    } else {
      researchRecords = []
      researchProviderErrors = [:]
      researchProviderCounts = [:]
      researchPagination = [:]
      researchRequests = [:]
    }
    guard searchScope != .research else {
      isSearching = false
      status = .searchingProviders(ResearchProviderID.allCases.count)
      return
    }
    requestedMediaType = mediaType
    isSearching = true
    isLoadingMore = false
    providerErrors = [:]
    if providerID == nil {
      providerCounts = [:]
      providerModes = [:]
      pagination = [:]
      loadMoreInFlight = [:]
      loadMoreFailedProviders = []
      candidateAssets = []
      assets = []
    } else {
      pagination[providerID!] = []
      candidateAssets.removeAll { $0.provider == providerID }
      rerankAssets()
    }
    status = .searchingProviders(selectedProviders.count)
    let filterSnapshot = (
      mediaType, orientation, resolution, duration, yearFrom, yearTo, downloadableOnly
    )
    let providerSet = providerID.map { Set([$0]) } ?? selectedProviders
    let providers = makeProviders(directOverrides: directOverrides).filter {
      providerSet.contains($0.info.id)
    }
    refreshProviderConfiguration()
    for provider in providers { setInitialState(for: provider) }
    for provider in providers
    where provider.info.requiresAPIKey && KeychainService.read(provider.info.id).isEmpty {
      providerStates[provider.info.id] = ProviderRuntimeState(
        availability: .authenticationRequired,
        message: ProviderError.missingAPIKey(provider.info.id).errorDescription)
    }
    task = Task { [weak self] in
      guard let self else { return }
      await withTaskGroup(of: ProviderSearchResult.self) { group in
        for provider in providers {
          group.addTask {
            var combined: [MediaAsset] = []
            var nextPages: [ProviderQueryPageState] = []
            var totalResults = 0
            do {
              let providerKeywords = KeywordEngine.providerKeywordPlan(
                from: activeKeywords, provider: provider.info.id, mode: provider.info.mode)
              let outcomes = await Self.searchQueries(
                providerKeywords, provider: provider, forceRefresh: forceRefresh,
                filter: filterSnapshot)
              var firstError: Error?
              for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
                if let error = outcome.error {
                  firstError = firstError ?? error
                  await AppLogger.shared.write(
                    provider: provider.info.id, requestType: "search", error: error)
                  continue
                }
                guard let page = outcome.page else { continue }
                let request = SearchRequest(
                  query: outcome.keyword.text, mediaType: filterSnapshot.0,
                  orientation: filterSnapshot.1, resolution: filterSnapshot.2,
                  duration: filterSnapshot.3, yearFrom: filterSnapshot.4,
                  yearTo: filterSnapshot.5, downloadableOnly: filterSnapshot.6, pageSize: 16)
                combined += page.assets.map { asset in
                  var ranked = asset
                  ranked.originalMetadata["matchedQuery"] = outcome.keyword.text
                  if let language = outcome.keyword.language {
                    ranked.originalMetadata["matchedQueryLanguage"] = language.rawValue
                  }
                  if let origin = outcome.keyword.origin {
                    ranked.originalMetadata["matchedQueryOrigin"] = origin.rawValue
                  }
                  ranked.originalMetadata["matchedQueryPriority"] = String(
                    outcome.keyword.priority ?? outcome.index)
                  return ranked
                }
                if let continuation = page.continuation {
                  nextPages.append(
                    ProviderQueryPageState(request: request, continuation: continuation))
                }
                if let total = page.totalResults { totalResults += total }
              }
              if combined.isEmpty, let firstError { throw firstError }
              return ProviderSearchResult(
                provider: provider.info.id, assets: combined, error: nil, state: nil,
                mode: provider.info.mode, pagination: nextPages,
                totalResults: totalResults > 0 ? totalResults : nil)
            } catch {
              await AppLogger.shared.write(
                provider: provider.info.id, requestType: "search", error: error)
              let providerError =
                error as? ProviderError ?? ProviderError.message(error.localizedDescription)
              return ProviderSearchResult(
                provider: provider.info.id, assets: combined, error: providerError,
                state: ProviderRuntimeState.from(error: error), mode: provider.info.mode)
            }
          }
        }
        for await batch in group {
          if Task.isCancelled {
            group.cancelAll()
            break
          }
          guard self.searchGeneration == generation else { continue }
          self.apply(batch)
        }
      }
      guard self.searchGeneration == generation else { return }
      if Task.isCancelled {
        self.isSearching = false
        self.status = .stopped
        return
      }
      self.isSearching = false
      self.status = self.assets.isEmpty ? .noResults : .found(self.assets.count)
      self.saveHistory(active: active)
    }
  }

  func stop() {
    task?.cancel()
    researchTask?.cancel()
    task = nil
    researchTask = nil
    isSearching = false
    isResearchSearching = false
    isLoadingMore = false
    isLoadingMoreResearch = false
    status = .stopped
  }

  /// Reuses the existing media search view model and relevance pipeline. The
  /// user can inspect or edit the short hint set before any provider request.
  func findRelatedMedia(_ record: ResearchRecord) {
    let hints = record.relatedMediaQueryHints.filter { !$0.isEmpty }
    query = hints.first ?? record.title
    keywords = hints.enumerated().map { index, hint in
      SearchKeyword(
        text: hint, language: record.language, origin: index == 0 ? .input : .userAdded,
        priority: index)
    }
    searchScope = .media
    search(forceRefresh: true)
  }

  /// Adds only a source-confirmed public-domain image to the existing media
  /// result pipeline. Other research records remain references/discovery only.
  func addResearchRecordAsMedia(_ record: ResearchRecord) {
    guard let asset = ResearchMediaAdapter.asset(for: record) else { return }
    searchScope = .media
    mediaType = .image
    assets = [asset]
    candidateAssets = [asset]
    status = .found(1)
  }

  private func startResearchSearch(active: [String], generation: UUID) {
    isResearchSearching = true
    researchRecords = []
    researchProviderErrors = [:]
    researchProviderCounts = [:]
    researchPagination = [:]
    researchRequests = [:]
    let plan = ResearchQueryPlanner.queries(for: query, interfaceLanguage: searchInterfaceLanguage)
    let primary = plan.first?.text ?? active.first ?? query
    let english = plan.first(where: { $0.language == .english })?.text ?? primary
    let interfaceLanguage = searchInterfaceLanguage
    let relevance = relevanceMode
    let inputLanguage = searchInputLanguage
    let selectedProviderIDs = selectedResearchProviders
    researchTask = Task { [weak self] in
      guard let self else { return }
      await withTaskGroup(of: ResearchProviderResult.self) { group in
        for providerID in ResearchProviderID.allCases where selectedProviderIDs.contains(providerID)
        {
          let provider = ResearchProviderFactory.make(providerID)
          let providerQuery =
            (providerID == .wikipedia || providerID == .wikidata) ? primary : english
          group.addTask {
            do {
              let initialRequest = ResearchSearchRequest(
                query: providerQuery, interfaceLanguage: interfaceLanguage)
              let page = try await provider.search(initialRequest, continuation: nil)
              // Wikipedia and Wikidata first honour the person's current UI
              // language.  A bounded English fallback only fills a genuinely
              // sparse result set; it never turns one research search into a
              // ten-language request fan-out.
              if providerID == .wikipedia || providerID == .wikidata,
                page.records.count < 4, english != providerQuery
              {
                let fallback = try await provider.search(
                  ResearchSearchRequest(query: english, interfaceLanguage: .english),
                  continuation: nil)
                let merged = ResearchRecordDeduplicator.apply(page.records + fallback.records)
                return ResearchProviderResult(
                  provider: providerID, records: merged, error: nil,
                  continuation: page.continuation ?? fallback.continuation,
                  totalResults: page.totalResults ?? fallback.totalResults)
              }
              return ResearchProviderResult(
                provider: providerID, records: page.records, error: nil,
                continuation: page.continuation, totalResults: page.totalResults)
            } catch {
              let providerError = error as? ProviderError ?? .message(error.localizedDescription)
              // AppLogger currently models media provider ids. Use Wikimedia as
              // an audit category while retaining the research source in type.
              await AppLogger.shared.write(
                provider: .wikimedia, requestType: "research-\(providerID.rawValue)", error: error)
              return ResearchProviderResult(
                provider: providerID, records: [], error: providerError,
                continuation: nil, totalResults: nil)
            }
          }
        }
        for await result in group {
          guard !Task.isCancelled, self.searchGeneration == generation else {
            group.cancelAll()
            break
          }
          if let error = result.error {
            self.researchProviderErrors[result.provider] = error
            continue
          }
          self.researchProviderErrors[result.provider] = nil
          self.researchRecords += result.records
          self.researchRecords = ResearchRecordDeduplicator.apply(self.researchRecords)
          self.researchRecords = ResearchRelevanceEngine.rank(
            self.researchRecords, query: self.query, mode: relevance,
            supportingQueries: active, inputLanguage: inputLanguage,
            interfaceLanguage: interfaceLanguage)
          self.researchProviderCounts[result.provider] =
            self.researchRecords.filter {
              $0.provider == result.provider
            }.count
          if let continuation = result.continuation {
            self.researchPagination[result.provider] = continuation
            self.researchRequests[result.provider] = ResearchSearchRequest(
              query: result.records.first?.searchKeyword
                ?? ((result.provider == .wikipedia || result.provider == .wikidata)
                  ? primary : english),
              interfaceLanguage: interfaceLanguage)
          } else {
            self.researchPagination[result.provider] = nil
          }
        }
      }
      guard self.searchGeneration == generation else { return }
      self.isResearchSearching = false
      if self.searchScope == .research {
        self.status =
          self.researchRecords.isEmpty ? .noResults : .foundResearch(self.researchRecords.count)
        self.saveHistory(active: active, resultCount: self.researchRecords.count)
      }
    }
  }

  func loadMore(only providerID: ProviderID? = nil) {
    guard !isSearching, !isLoadingMore else { return }
    let eligible = pagination.keys.filter { id in
      (providerID == nil || providerID == id) && !(pagination[id]?.isEmpty ?? true)
    }
    guard !eligible.isEmpty else { return }
    let providers = makeProviders(directOverrides: []).filter { eligible.contains($0.info.id) }
    guard !providers.isEmpty else { return }
    let generation = searchGeneration
    isLoadingMore = true
    for provider in providers {
      guard var states = pagination[provider.info.id], !states.isEmpty else { continue }
      let next = states.removeFirst()
      pagination[provider.info.id] = states
      loadMoreInFlight[provider.info.id] = next
    }
    task = Task { [weak self] in
      guard let self else { return }
      await withTaskGroup(of: ProviderSearchResult.self) { group in
        for provider in providers {
          guard let state = self.loadMoreInFlight[provider.info.id] else { continue }
          group.addTask {
            do {
              let page = try await provider.searchPage(
                state.request, continuation: state.continuation)
              let nextState = page.continuation.map {
                ProviderQueryPageState(request: state.request, continuation: $0)
              }
              return ProviderSearchResult(
                provider: provider.info.id, assets: page.assets, error: nil, state: nil,
                mode: provider.info.mode, pagination: nextState.map { [$0] } ?? [],
                totalResults: page.totalResults)
            } catch {
              await AppLogger.shared.write(
                provider: provider.info.id, requestType: "load-more", error: error)
              let providerError =
                error as? ProviderError ?? ProviderError.message(error.localizedDescription)
              return ProviderSearchResult(
                provider: provider.info.id, assets: [], error: providerError,
                state: ProviderRuntimeState.from(error: error), mode: provider.info.mode)
            }
          }
        }
        for await batch in group {
          guard !Task.isCancelled, self.searchGeneration == generation else {
            group.cancelAll()
            break
          }
          self.applyLoadMore(batch)
        }
      }
      guard self.searchGeneration == generation else { return }
      self.isLoadingMore = false
      self.status = self.assets.isEmpty ? .noResults : .found(self.assets.count)
    }
  }

  func loadMoreResearch(only providerID: ResearchProviderID? = nil) {
    guard !isResearchSearching, !isLoadingMoreResearch else { return }
    let eligible = researchPagination.keys.filter { providerID == nil || $0 == providerID }
    guard !eligible.isEmpty else { return }
    let generation = searchGeneration
    isLoadingMoreResearch = true
    let relevance = relevanceMode
    let interfaceLanguage = searchInterfaceLanguage
    let inputLanguage = searchInputLanguage
    let supporting = relevanceQueries
    researchTask = Task { [weak self] in
      guard let self else { return }
      await withTaskGroup(of: ResearchProviderResult.self) { group in
        for id in eligible {
          guard let continuation = self.researchPagination[id],
            let request = self.researchRequests[id]
          else { continue }
          group.addTask {
            do {
              let page = try await ResearchProviderFactory.make(id).search(
                request, continuation: continuation)
              return ResearchProviderResult(
                provider: id, records: page.records, error: nil,
                continuation: page.continuation, totalResults: page.totalResults)
            } catch {
              return ResearchProviderResult(
                provider: id, records: [],
                error: error as? ProviderError ?? .message(error.localizedDescription),
                continuation: continuation, totalResults: nil)
            }
          }
        }
        for await result in group {
          guard !Task.isCancelled, self.searchGeneration == generation else {
            group.cancelAll()
            break
          }
          if let error = result.error {
            self.researchProviderErrors[result.provider] = error
            continue
          }
          self.researchProviderErrors[result.provider] = nil
          self.researchRecords = ResearchRecordDeduplicator.apply(
            self.researchRecords + result.records)
          self.researchRecords = ResearchRelevanceEngine.rank(
            self.researchRecords, query: self.query, mode: relevance, supportingQueries: supporting,
            inputLanguage: inputLanguage, interfaceLanguage: interfaceLanguage)
          self.researchProviderCounts[result.provider] =
            self.researchRecords.filter { $0.provider == result.provider }.count
          self.researchPagination[result.provider] = result.continuation
        }
      }
      guard self.searchGeneration == generation else { return }
      self.isLoadingMoreResearch = false
      self.status =
        self.researchRecords.isEmpty ? .noResults : .foundResearch(self.researchRecords.count)
    }
  }

  func tryDirectSearch(_ providerID: ProviderID) {
    guard providerID == .pexels || providerID == .pixabay else { return }
    search(forceRefresh: true, only: providerID, directOverrides: [providerID])
  }

  private func makeProviders(directOverrides: Set<ProviderID>) -> [any MediaProvider] {
    ProviderID.searchCases.map { id in
      ProviderFactory.make(
        id, apiKey: directOverrides.contains(id) ? "" : KeychainService.read(id))
    }
  }

  private func apply(_ batch: ProviderSearchResult) {
    providerModes[batch.provider] = batch.mode
    loadMoreFailedProviders.remove(batch.provider)
    pagination[batch.provider] = batch.pagination
    if let error = batch.error {
      providerErrors[batch.provider] = error
      var state =
        batch.state
        ?? ProviderRuntimeState(availability: .unavailable, message: error.errorDescription)
      state.mode = batch.mode
      providerStates[batch.provider] = state
    } else {
      providerErrors[batch.provider] = nil
      let availability: ProviderAvailability =
        switch batch.mode {
        case .officialAPI: .apiConnected
        case .publicAPI: .publicAPI
        case .limited: .limitedMode
        case .directSearch, .ytDLP: .bestEffort
        case .publicInterface: .available
        }
      providerStates[batch.provider] = ProviderRuntimeState(
        availability: availability, message: nil, mode: batch.mode)
    }
    candidateAssets += batch.assets
    candidateAssets = SearchDeduplicator.apply(candidateAssets)
    rerankAssets()
    providerCounts[batch.provider] = assets.filter { $0.provider == batch.provider }.count
    status = assets.isEmpty ? .searchingOthers : .progressiveFound(assets.count)
  }

  private func applyLoadMore(_ batch: ProviderSearchResult) {
    guard let original = loadMoreInFlight.removeValue(forKey: batch.provider) else { return }
    providerModes[batch.provider] = batch.mode
    if let error = batch.error {
      pagination[batch.provider, default: []].insert(original, at: 0)
      loadMoreFailedProviders.insert(batch.provider)
      providerErrors[batch.provider] = error
      var state = batch.state ?? ProviderRuntimeState.from(error: error)
      state.mode = batch.mode
      providerStates[batch.provider] = state
      return
    }
    providerErrors[batch.provider] = nil
    loadMoreFailedProviders.remove(batch.provider)
    pagination[batch.provider, default: []].append(contentsOf: batch.pagination)
    candidateAssets += batch.assets
    candidateAssets = SearchDeduplicator.apply(candidateAssets)
    rerankAssets()
    providerCounts[batch.provider] = assets.filter { $0.provider == batch.provider }.count
    let availability: ProviderAvailability =
      switch batch.mode {
      case .officialAPI: .apiConnected
      case .publicAPI: .publicAPI
      case .limited: .limitedMode
      case .directSearch, .ytDLP: .bestEffort
      case .publicInterface: .available
      }
    providerStates[batch.provider] = ProviderRuntimeState(
      availability: availability, message: nil, mode: batch.mode)
    status = .progressiveFound(assets.count)
  }

  private func score(_ asset: MediaAsset) -> Double {
    asset.relevanceScore + (asset.isDirectlyDownloadable ? 0.08 : 0)
      + (asset.height ?? 0 >= 1080 ? 0.04 : 0)
      + (asset.creator != nil ? 0.01 : 0) + (asset.licenseStatus != .unknown ? 0.03 : 0)
  }

  private func rerankAssets() {
    let relevanceQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !relevanceQuery.isEmpty else {
      assets = candidateAssets
      return
    }
    assets = SearchRelevanceEngine.rank(
      candidateAssets, query: relevanceQuery, mode: relevanceMode,
      supportingQueries: relevanceQueries, inputLanguage: searchInputLanguage,
      interfaceLanguage: searchInterfaceLanguage)
  }

  private func setInitialState(for provider: any MediaProvider) {
    providerModes[provider.info.id] = provider.info.mode
    let availability: ProviderAvailability =
      switch provider.info.mode {
      case .officialAPI, .publicInterface: .available
      case .publicAPI: .publicAPI
      case .limited: .limitedMode
      case .directSearch, .ytDLP: .bestEffort
      }
    providerStates[provider.info.id] = ProviderRuntimeState(
      availability: availability, message: nil, mode: provider.info.mode)
  }

  private func saveHistory(active: [String], resultCount: Int? = nil) {
    guard let store else { return }
    let record = SearchHistoryRecord(
      originalQuery: query, keywords: active, providers: selectedProviders,
      projectID: currentProjectID, resultCount: resultCount ?? assets.count,
      keywordDetails: keywords.filter(\.isEnabled))
    store.addHistory(record)
  }

  nonisolated private static func searchQueries(
    _ keywords: [SearchKeyword], provider: any MediaProvider, forceRefresh: Bool,
    filter: (
      MediaType, AssetOrientation, ResolutionFilter, DurationFilter, Int?, Int?, Bool
    )
  ) async -> [ProviderQueryOutcome] {
    guard !keywords.isEmpty else { return [] }
    let concurrency = provider.info.mode == .directSearch || provider.info.mode == .ytDLP ? 1 : 2
    return await withTaskGroup(of: ProviderQueryOutcome.self) { group in
      var nextIndex = 0
      func enqueue(_ index: Int) {
        let keyword = keywords[index]
        group.addTask {
          if Task.isCancelled {
            return ProviderQueryOutcome(
              index: index, keyword: keyword, page: nil, error: ProviderError.cancelled)
          }
          await SearchRequestLimiter.shared.acquire()
          if Task.isCancelled {
            await SearchRequestLimiter.shared.release()
            return ProviderQueryOutcome(
              index: index, keyword: keyword, page: nil, error: ProviderError.cancelled)
          }
          let request = SearchRequest(
            query: keyword.text, mediaType: filter.0, orientation: filter.1,
            resolution: filter.2, duration: filter.3, yearFrom: filter.4,
            yearTo: filter.5, downloadableOnly: filter.6, pageSize: 16)
          do {
            let page: ProviderPage
            if !forceRefresh, provider.info.id != .nationalArchives,
              let cached = await SearchCache.shared.page(
                provider: provider.info.id, request: request)
            {
              page = cached
            } else {
              page = try await provider.searchPage(request, continuation: nil)
              if provider.info.id != .nationalArchives {
                await SearchCache.shared.store(
                  page, provider: provider.info.id, request: request)
              }
            }
            await SearchRequestLimiter.shared.release()
            return ProviderQueryOutcome(index: index, keyword: keyword, page: page, error: nil)
          } catch {
            await SearchRequestLimiter.shared.release()
            return ProviderQueryOutcome(index: index, keyword: keyword, page: nil, error: error)
          }
        }
      }

      while nextIndex < min(concurrency, keywords.count) {
        enqueue(nextIndex)
        nextIndex += 1
      }
      var results: [ProviderQueryOutcome] = []
      var halted = false
      for await outcome in group {
        results.append(outcome)
        if let providerError = outcome.error as? ProviderError {
          switch providerError {
          case .rateLimited, .temporarilyBlocked, .invalidAPIKey, .missingAPIKey:
            halted = true
          default:
            break
          }
        }
        if nextIndex < keywords.count, !Task.isCancelled, !halted {
          enqueue(nextIndex)
          nextIndex += 1
        }
      }
      return results
    }
  }
}

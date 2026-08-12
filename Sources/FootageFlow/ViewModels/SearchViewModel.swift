import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
  @Published var query = ""
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
  @Published private(set) var assets: [MediaAsset] = []
  @Published private(set) var providerErrors: [ProviderID: ProviderError] = [:]
  @Published private(set) var providerCounts: [ProviderID: Int] = [:]
  @Published private(set) var providerStates: [ProviderID: ProviderRuntimeState] = [:]
  @Published private(set) var providerModes: [ProviderID: ProviderMode] = [:]
  @Published private(set) var isSearching = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var loadMoreFailedProviders = Set<ProviderID>()
  @Published private(set) var status: SearchStatus = .initial

  private var task: Task<Void, Never>?
  private var store: DataStore?
  private var candidateAssets: [MediaAsset] = []
  private var relevanceQueries: [String] = []
  private var pagination: [ProviderID: [ProviderQueryPageState]] = [:]
  private var loadMoreInFlight: [ProviderID: ProviderQueryPageState] = [:]
  private var searchGeneration = UUID()

  var statusText: String { status.text }
  var canLoadMore: Bool { !pagination.values.allSatisfy(\.isEmpty) }
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

  func prepareKeywords(translated: String? = nil) {
    keywords = KeywordEngine.keywords(
      for: query, translated: translated, smartExpansion: smartExpansionEnabled)
  }
  func acceptTranslation(_ text: String) {
    keywords = KeywordEngine.mergeTranslation(text, into: keywords)
  }
  func addKeyword() { keywords.append(SearchKeyword(text: "")) }
  func removeKeyword(_ id: UUID) { keywords.removeAll { $0.id == id } }

  func search(
    forceRefresh: Bool = false, only providerID: ProviderID? = nil,
    directOverrides: Set<ProviderID> = []
  ) {
    let active = keywords.filter {
      $0.isEnabled && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
    }.map(\.text)
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
    let generation = UUID()
    searchGeneration = generation
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
              let providerKeywords = KeywordEngine.providerQueries(
                from: active.map { SearchKeyword(text: $0) }, provider: provider.info.id,
                mode: provider.info.mode)
              for (queryIndex, keyword) in providerKeywords.enumerated() {
                try Task.checkCancellation()
                let request = SearchRequest(
                  query: keyword, mediaType: filterSnapshot.0, orientation: filterSnapshot.1,
                  resolution: filterSnapshot.2, duration: filterSnapshot.3,
                  yearFrom: filterSnapshot.4, yearTo: filterSnapshot.5,
                  downloadableOnly: filterSnapshot.6, pageSize: 16)
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
                combined += page.assets.map { asset in
                  var ranked = asset
                  ranked.relevanceScore -= Double(queryIndex) * 0.08
                  ranked.originalMetadata["matchedQuery"] = keyword
                  return ranked
                }
                if let continuation = page.continuation {
                  nextPages.append(
                    ProviderQueryPageState(request: request, continuation: continuation))
                }
                if let total = page.totalResults { totalResults += total }
              }
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
    task = nil
    isSearching = false
    isLoadingMore = false
    status = .stopped
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
      supportingQueries: relevanceQueries)
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

  private func saveHistory(active: [String]) {
    guard let store else { return }
    let record = SearchHistoryRecord(
      originalQuery: query, keywords: active, providers: selectedProviders,
      projectID: currentProjectID, resultCount: assets.count)
    store.addHistory(record)
  }
}

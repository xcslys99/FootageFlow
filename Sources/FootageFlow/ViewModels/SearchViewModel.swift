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
    @Published var sort: SearchSort = .relevance
    @Published var selectedProviders = AppSettings.enabledProviders
    @Published var currentProjectID: UUID?
    @Published private(set) var assets: [MediaAsset] = []
    @Published private(set) var providerErrors: [ProviderID: String] = [:]
    @Published private(set) var providerCounts: [ProviderID: Int] = [:]
    @Published private(set) var providerStates: [ProviderID: ProviderRuntimeState] = [:]
    @Published private(set) var isSearching = false
    @Published private(set) var statusText = "输入题材后搜索真实素材库"

    private var task: Task<Void, Never>?
    private var store: DataStore?

    var filteredAssets: [MediaAsset] {
        var value = assets.filter { asset in
            (mediaType == .all || asset.mediaType == mediaType) &&
            (orientation == .all || asset.orientation == orientation) &&
            (resolution.minimumHeight == nil || (asset.height ?? 0) >= resolution.minimumHeight!) &&
            duration.matches(asset.duration) && licenseFilter.matches(asset.licenseStatus) &&
            selectedProviders.contains(asset.provider)
        }
        switch sort {
        case .relevance: value.sort { score($0) > score($1) }
        case .newest: value.sort { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        case .resolution: value.sort { ($0.width ?? 0) * ($0.height ?? 0) > ($1.width ?? 0) * ($1.height ?? 0) }
        case .duration: value.sort { ($0.duration ?? -1) > ($1.duration ?? -1) }
        }
        return value
    }

    func configure(store: DataStore) { self.store = store }

    func prepareKeywords(translated: String? = nil) { keywords = KeywordEngine.keywords(for: query, translated: translated) }
    func acceptTranslation(_ text: String) { keywords = KeywordEngine.mergeTranslation(text, into: keywords) }
    func addKeyword() { keywords.append(SearchKeyword(text: "")) }
    func removeKeyword(_ id: UUID) { keywords.removeAll { $0.id == id } }

    func search(forceRefresh: Bool = false, only providerID: ProviderID? = nil) {
        let active = keywords.filter { $0.isEnabled && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.text)
        guard !active.isEmpty else { prepareKeywords(); if keywords.isEmpty { statusText = "请先输入搜索内容"; return }; search(forceRefresh: forceRefresh, only: providerID); return }
        task?.cancel()
        isSearching = true; providerErrors = [:]; providerCounts = [:]
        statusText = "正在并发搜索 \(selectedProviders.count) 个素材库…"
        let filterSnapshot = (mediaType, orientation, resolution, duration)
        let providerSet = providerID.map { Set([$0]) } ?? selectedProviders
        let providers = makeProviders().filter { providerSet.contains($0.info.id) }
        for id in ProviderID.allCases {
            providerStates[id] = selectedProviders.contains(id)
                ? ProviderRuntimeState(availability: .available, message: nil)
                : ProviderRuntimeState(availability: .disabled, message: nil)
        }
        for provider in providers where provider.info.requiresAPIKey && KeychainService.read(provider.info.id).isEmpty {
            providerStates[provider.info.id] = ProviderRuntimeState(availability: .authenticationRequired, message: ProviderError.missingAPIKey(provider.info.id).errorDescription)
        }
        task = Task { [weak self] in
            guard let self else { return }
            if providerID == nil { self.assets = [] }
            await withTaskGroup(of: ProviderSearchResult.self) { group in
                for provider in providers {
                    group.addTask {
                        var combined: [MediaAsset] = []
                        do {
                            let providerKeywords = provider.info.id == .youtube ? Array(active.prefix(2)) : active
                            for keyword in providerKeywords {
                                try Task.checkCancellation()
                                let request = SearchRequest(query: keyword, mediaType: filterSnapshot.0, orientation: filterSnapshot.1, resolution: filterSnapshot.2, duration: filterSnapshot.3, pageSize: 16)
                                if !forceRefresh, let cached = await SearchCache.shared.assets(provider: provider.info.id, request: request) { combined += cached }
                                else {
                                    let found = try await provider.search(request)
                                    await SearchCache.shared.store(found, provider: provider.info.id, request: request)
                                    combined += found
                                }
                            }
                            return ProviderSearchResult(provider: provider.info.id, assets: combined, errorMessage: nil, state: nil)
                        } catch {
                            await AppLogger.shared.write(provider: provider.info.id, requestType: "search", error: error)
                            return ProviderSearchResult(provider: provider.info.id, assets: combined, errorMessage: (error as? LocalizedError)?.errorDescription ?? "搜索失败", state: ProviderRuntimeState.from(error: error))
                        }
                    }
                }
                for await batch in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    self.apply(batch)
                }
            }
            if Task.isCancelled { self.isSearching = false; self.statusText = "搜索已停止"; return }
            self.isSearching = false
            self.statusText = self.assets.isEmpty ? "没有找到结果，可修改关键词后重试" : "已找到 \(self.assets.count) 条真实素材"
            self.saveHistory(active: active)
        }
    }

    func stop() { task?.cancel(); task = nil; isSearching = false; statusText = "搜索已停止" }

    private func makeProviders() -> [any MediaProvider] {
        [
            PexelsProvider(apiKey: KeychainService.read(.pexels)),
            PixabayProvider(apiKey: KeychainService.read(.pixabay)),
            WikimediaProvider(), InternetArchiveProvider(),
            YouTubeProvider(apiKey: KeychainService.read(.youtube))
        ]
    }

    private func apply(_ batch: ProviderSearchResult) {
        providerCounts[batch.provider] = batch.assets.count
        if let message = batch.errorMessage {
            providerErrors[batch.provider] = message
            providerStates[batch.provider] = batch.state ?? ProviderRuntimeState(availability: .unavailable, message: message)
        } else {
            providerErrors[batch.provider] = nil
            providerStates[batch.provider] = ProviderRuntimeState(availability: .available, message: nil)
        }
        assets += batch.assets
        assets = SearchDeduplicator.apply(assets).prefix(300).map { $0 }
        statusText = assets.isEmpty ? "正在搜索其他素材库…" : "已找到 \(assets.count) 条真实素材，其他来源仍在搜索…"
    }

    private func score(_ asset: MediaAsset) -> Double {
        asset.relevanceScore + (asset.downloadable ? 0.08 : 0) + (asset.height ?? 0 >= 1080 ? 0.04 : 0) + (asset.creator != nil ? 0.01 : 0) + (asset.licenseStatus != .unknown ? 0.03 : 0)
    }

    private func saveHistory(active: [String]) {
        guard let store else { return }
        let record = SearchHistoryRecord(originalQuery: query, keywords: active, providers: selectedProviders, projectID: currentProjectID, resultCount: assets.count)
        store.addHistory(record)
    }
}

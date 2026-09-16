import SwiftUI
import Translation

struct QuickSearchView: View {
  var onManageSources: () -> Void = {}
  @EnvironmentObject private var viewModel: SearchViewModel
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var localization: LocalizationManager
  @EnvironmentObject private var workspace: WorkspaceCoordinator
  @State private var translationConfiguration: TranslationSession.Configuration?
  @State private var pendingTranslation = ""
  @State private var showHistory = false
  @State private var selection = AssetSelection()
  @State private var showAdvancedFilters = false
  @State private var showSourceFilters = false
  @State private var showLimitedSourceNotices = false
  @State private var showAllSearchLanguages = false
  @State private var showNewProject = false
  @State private var newProjectName = ""
  @State private var showSaveSearch = false
  @State private var savedSearchName = ""
  @FocusState private var searchFieldFocused: Bool

  private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      searchHeader
      Divider()
      if viewModel.isAnySearching { ProgressView().progressViewStyle(.linear) }
      statusArea
      if viewModel.searchScope != .research { selectionBar }
      if !viewModel.isAnySearching && !viewModel.query.isEmpty && isEmptyResult {
        ContentUnavailableView(
          tr("search.emptyTitle"), systemImage: "film.stack",
          description: Text(tr("search.emptyDescription"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if viewModel.searchScope != .research {
              if viewModel.searchScope == .all {
                Text(tr("search.scope.media")).font(.headline).frame(
                  maxWidth: .infinity, alignment: .leading)
              }
              LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(viewModel.filteredAssets) { asset in
                  MediaAssetCard(
                    asset: asset, projectID: viewModel.currentProjectID, segmentIndex: nil,
                    isSelected: selection.contains(asset),
                    onToggleSelection: { selection.toggle($0) }
                  ) { PreviewWindowManager.shared.show($0) }
                }
              }
            }
            if viewModel.searchScope != .media {
              if viewModel.searchScope == .all {
                Text(tr("search.scope.research")).font(.headline).frame(
                  maxWidth: .infinity, alignment: .leading
                ).padding(.top, 20)
              }
              LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(viewModel.filteredResearchRecords) { record in
                  ResearchRecordCard(
                    record: record, projectID: viewModel.currentProjectID,
                    onFindRelatedMedia: { viewModel.findRelatedMedia($0) },
                    onAddAsMedia: { viewModel.addResearchRecordAsMedia($0) })
                }
              }
            }
          }
          .padding(16)
          if viewModel.searchScope != .research && viewModel.isLoadingMore {
            ProgressView(tr("search.loadingMore")).padding(.bottom, 20)
          } else if viewModel.searchScope != .research && viewModel.canLoadMore {
            Button {
              viewModel.loadMore()
            } label: {
              Label(tr("search.loadMore"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
          }
          if viewModel.searchScope != .media && viewModel.isLoadingMoreResearch {
            ProgressView(tr("search.loadingMore")).padding(.bottom, 20)
          } else if viewModel.searchScope != .media && viewModel.canLoadMoreResearch {
            Button {
              viewModel.loadMoreResearch()
            } label: {
              Label(tr("search.loadMore"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
          }
        }
      }
    }
    .navigationTitle(tr("nav.quickSearch"))
    .toolbar {
      ToolbarItemGroup {
        Button {
          savedSearchName = viewModel.query
          showSaveSearch = true
        } label: {
          Label(tr("workspace.saveSearch"), systemImage: "bookmark")
        }
        .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button {
          showHistory = true
        } label: {
          Label(tr("search.history"), systemImage: "clock.arrow.circlepath")
        }
        Button {
          viewModel.search(forceRefresh: true)
        } label: {
          Label(tr("search.refresh"), systemImage: "arrow.clockwise")
        }.disabled(viewModel.isAnySearching || viewModel.keywords.isEmpty)
      }
    }
    .sheet(isPresented: $showHistory) { SearchHistoryView(onUse: useHistory) }
    .sheet(isPresented: $showSaveSearch) {
      VStack(alignment: .leading, spacing: 16) {
        Text(tr("workspace.saveSearch")).font(.title2.bold())
        TextField(tr("workspace.savedSearchName"), text: $savedSearchName)
          .textFieldStyle(.roundedBorder)
          .onSubmit { saveCurrentSearch() }
        HStack {
          Spacer()
          Button(tr("common.cancel")) { showSaveSearch = false }
          Button(tr("common.save")) { saveCurrentSearch() }
            .buttonStyle(.borderedProminent)
            .disabled(savedSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(24).frame(width: 420)
    }
    .sheet(isPresented: $showNewProject) {
      VStack(alignment: .leading, spacing: 16) {
        Text(tr("project.new")).font(.title2.bold())
        TextField(tr("project.name"), text: $newProjectName).textFieldStyle(.roundedBorder)
        HStack {
          Spacer()
          Button(tr("common.cancel")) { showNewProject = false }
          Button(tr("common.create")) { createProjectAndAddSelection() }
            .buttonStyle(.borderedProminent)
            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.padding(24).frame(width: 420)
    }
    .onAppear {
      viewModel.selectedProviders = AppSettings.enabledProviders
      viewModel.refreshProviderConfiguration()
    }
    .onChange(of: viewModel.assets.map(\.stableID)) { _, _ in
      selection.retainAvailable(viewModel.assets)
    }
    .onChange(of: workspace.searchFocusRequest) { _, _ in searchFieldFocused = true }
    .translationTask(translationConfiguration) { session in
      guard !pendingTranslation.isEmpty else { return }
      do {
        let response = try await session.translate(pendingTranslation)
        await MainActor.run {
          viewModel.acceptTranslation(response.targetText)
          viewModel.search()
        }
      } catch {
        await MainActor.run { viewModel.search() }
      }
      await MainActor.run { pendingTranslation = "" }
    }
  }

  private var searchHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(tr("search.tagline")).font(.callout).foregroundStyle(.secondary)
      Picker(tr("search.scope"), selection: $viewModel.searchScope) {
        ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
      }
      .id(localization.language)
      .pickerStyle(.segmented).frame(maxWidth: 360)
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
        TextField(tr("search.placeholder"), text: $viewModel.query)
          .textFieldStyle(.plain).font(.title3).focused($searchFieldFocused)
          .accessibilityLabel(tr("search.placeholder"))
          .onSubmit { beginSearch() }
        if viewModel.isAnySearching {
          Button(tr("common.stop")) { viewModel.stop() }.buttonStyle(.bordered)
        } else {
          Button(tr("search.button")) { beginSearch() }.buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
      }
      .padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

      Button(action: onManageSources) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "info.circle")
          Text(tr("search.apiRecommendation"))
            .multilineTextAlignment(.leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(tr("settings.manageSources"))

      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text(tr("search.currentKeywords")).foregroundStyle(.secondary).padding(.top, 4)
          Toggle(tr("search.smartExpansion"), isOn: $viewModel.smartExpansionEnabled)
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.smartExpansionEnabled) { _, _ in
              viewModel.prepareKeywords(interfaceLanguage: localization.language)
            }
        }
        VStack(alignment: .leading, spacing: 5) {
          ForEach(visibleKeywordIndices, id: \.self) { index in
            let keyword = $viewModel.keywords[index]
            HStack(spacing: 6) {
              Toggle("", isOn: keyword.isEnabled).labelsHidden()
                .accessibilityLabel(
                  tr("accessibility.keywordEnabled", keyword.wrappedValue.text))
              if let language = keyword.wrappedValue.language {
                Text(language.displayName)
                  .font(.caption2).foregroundStyle(.secondary)
                  .frame(width: 78, alignment: .leading)
              }
              TextField(tr("search.keywordPlaceholder"), text: keyword.text).textFieldStyle(
                .roundedBorder)
              Button {
                viewModel.removeKeyword(keyword.wrappedValue.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
              }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(tr("common.delete"))
            }
          }
          Button {
            viewModel.addKeyword()
          } label: {
            Label(tr("search.addKeyword"), systemImage: "plus")
          }.buttonStyle(.plain)
          if viewModel.keywords.count > visibleKeywordIndices.count || showAllSearchLanguages {
            Button {
              withAnimation { showAllSearchLanguages.toggle() }
            } label: {
              Label(
                tr(showAllSearchLanguages ? "search.hideAllLanguages" : "search.showAllLanguages"),
                systemImage: showAllSearchLanguages ? "chevron.up" : "globe")
            }
            .buttonStyle(.plain)
          }
        }
      }
      if viewModel.searchScope != .research {
        HStack {
          Toggle(isOn: $viewModel.downloadableOnly) {
            Label(tr("filter.downloadableOnly"), systemImage: "arrow.down.circle.fill")
              .fontWeight(.semibold)
          }
          .toggleStyle(.checkbox)
          Button {
            withAnimation { showAdvancedFilters.toggle() }
          } label: {
            Label(tr("filter.advanced"), systemImage: "line.3.horizontal.decrease.circle")
          }.buttonStyle(.link)
          Button(tr("filter.clear")) { viewModel.clearFilters() }
            .buttonStyle(.link)
          Spacer()
        }
      }
      if viewModel.searchScope != .research {
        filters
      } else {
        researchFilters
        researchProviderStatusRow
      }
      projectPicker
    }
    .padding(16)
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker(
          tr("filter.type"),
          selection: Binding(
            get: { viewModel.mediaType },
            set: { viewModel.selectMediaType($0) })
        ) {
          ForEach(MediaType.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Picker(tr("filter.orientation"), selection: $viewModel.orientation) {
          ForEach(AssetOrientation.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Picker(tr("filter.resolution"), selection: $viewModel.resolution) {
          ForEach(ResolutionFilter.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 165)
        Picker(tr("filter.sort"), selection: $viewModel.sort) {
          ForEach(SearchSort.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Picker(tr("search.relevance.mode"), selection: $viewModel.relevanceMode) {
          ForEach(SearchRelevanceMode.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 155)
        Spacer()
      }
      if showAdvancedFilters {
        HStack {
          TextField(tr("filter.yearFrom"), text: yearFromBinding).frame(width: 110)
          Text("–").foregroundStyle(.secondary)
          TextField(tr("filter.yearTo"), text: yearToBinding).frame(width: 110)
          Picker(tr("filter.duration"), selection: $viewModel.duration) {
            ForEach(DurationFilter.allCases) { Text($0.label).tag($0) }
          }.id(localization.language).frame(width: 175)
          Picker(tr("filter.license"), selection: $viewModel.licenseFilter) {
            ForEach(LicenseFilter.allCases) { Text($0.label).tag($0) }
          }.id(localization.language).frame(width: 210)
          Spacer()
        }
      }
      Button {
        withAnimation { showSourceFilters.toggle() }
      } label: {
        Label(
          "\(tr("filter.source")) (\(viewModel.selectedProviders.count)/\(ProviderID.searchCases.count))",
          systemImage: "square.stack.3d.up")
        Image(systemName: showSourceFilters ? "chevron.up" : "chevron.down")
      }
      .buttonStyle(.bordered)
      if showSourceFilters {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
          alignment: .leading, spacing: 8
        ) {
          ForEach(ProviderID.searchCases) { provider in
            HStack(spacing: 5) {
              Toggle(
                provider.displayName,
                isOn: Binding(
                  get: { viewModel.selectedProviders.contains(provider) },
                  set: { enabled in
                    if enabled {
                      viewModel.selectedProviders.insert(provider)
                    } else {
                      viewModel.selectedProviders.remove(provider)
                    }
                    AppSettings.enabledProviders = viewModel.selectedProviders
                  })
              )
              .toggleStyle(.checkbox)
              .accessibilityLabel(tr("accessibility.providerEnabled", provider.displayName))
              if let count = viewModel.providerCounts[provider] {
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
              }
            }
            .help(
              "\(viewModel.providerModes[provider]?.label ?? "") · "
                + "\(viewModel.providerStates[provider]?.availability.label ?? "")")
          }
        }
        Button(tr("settings.manageSources"), systemImage: "slider.horizontal.3") {
          onManageSources()
        }.buttonStyle(.link)
      }
    }
  }

  /// Research records need the same explicit project choice as media assets. Keeping
  /// this outside media-only filters means “Add to Research Notes” is available in
  /// Research and All modes without changing the existing download workflow.
  private var projectPicker: some View {
    HStack {
      Picker(tr("common.project"), selection: $viewModel.currentProjectID) {
        Text(tr("common.uncategorized")).tag(Optional<UUID>.none)
        ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
      }
      .id(localization.language)
      .frame(width: 240)
      Spacer()
    }
  }

  private var researchFilters: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(tr("filter.yearFrom"), text: researchYearFromBinding).frame(width: 110)
        Text("–").foregroundStyle(.secondary)
        TextField(tr("filter.yearTo"), text: researchYearToBinding).frame(width: 110)
        Spacer()
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          Text(tr("research.type")).foregroundStyle(.secondary)
          ForEach(ResearchRecordType.allCases) { type in
            Toggle(
              type.label,
              isOn: Binding(
                get: { viewModel.selectedResearchTypes.contains(type) },
                set: { enabled in
                  if enabled {
                    viewModel.selectedResearchTypes.insert(type)
                  } else {
                    viewModel.selectedResearchTypes.remove(type)
                  }
                })
            )
            .toggleStyle(.checkbox)
            .accessibilityLabel(tr("accessibility.providerEnabled", type.label))
          }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          Text(tr("filter.source")).foregroundStyle(.secondary)
          ForEach(ResearchProviderID.allCases) { provider in
            Toggle(
              provider.displayName,
              isOn: Binding(
                get: { viewModel.selectedResearchProviders.contains(provider) },
                set: { enabled in
                  if enabled {
                    viewModel.selectedResearchProviders.insert(provider)
                  } else {
                    viewModel.selectedResearchProviders.remove(provider)
                  }
                })
            )
            .toggleStyle(.checkbox)
            .accessibilityLabel(tr("accessibility.providerEnabled", provider.displayName))
          }
        }
      }
    }
  }

  private var researchProviderStatusRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(
          ResearchProviderID.allCases.filter { viewModel.selectedResearchProviders.contains($0) }
        ) { provider in
          let failed = viewModel.researchProviderErrors[provider] != nil
          HStack(spacing: 5) {
            Circle().fill(failed ? Color.red : Color.green).frame(width: 7, height: 7)
            Text(provider.displayName)
            if let count = viewModel.researchProviderCounts[provider] {
              Text("\(count)").foregroundStyle(.secondary)
            }
          }
          .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
          .background(.quaternary.opacity(0.55), in: Capsule())
          .help(
            viewModel.researchProviderErrors[provider]?.errorDescription ?? tr("provider.available")
          )
        }
      }
    }
  }

  @ViewBuilder private var statusArea: some View {
    let limitedProviders = viewModel.providerErrors.keys.filter { provider in
      if case .limitedMode = viewModel.providerErrors[provider] { return true }
      return false
    }.sorted { $0.rawValue < $1.rawValue }
    let actionableProviders = viewModel.providerErrors.keys.filter {
      !limitedProviders.contains($0)
    }.sorted { $0.rawValue < $1.rawValue }
    if !actionableProviders.isEmpty || !viewModel.researchProviderErrors.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(actionableProviders, id: \.self) { provider in
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              Text(
                "\(provider.displayName): \(viewModel.providerErrors[provider]?.errorDescription ?? tr("search.failed"))"
              )
              .lineLimit(1)
              Button(tr("common.retry")) {
                if viewModel.loadMoreFailedProviders.contains(provider) {
                  viewModel.loadMore(only: provider)
                } else {
                  viewModel.search(only: provider)
                }
              }.buttonStyle(.link)
              if shouldOfferDirectSearch(provider) {
                Button(tr("provider.tryDirectSearch")) { viewModel.tryDirectSearch(provider) }
                  .buttonStyle(.link)
              }
              if shouldOfferAPIKey(provider) {
                Button(tr("settings.addAPIKey")) { onManageSources() }.buttonStyle(.link)
              }
              if let url = accessRestrictedSearchURL(provider) {
                Button(tr("provider.openOfficialSearch")) { DesktopPlatform.shared.open(url) }
                  .buttonStyle(.link)
              }
            }.padding(.horizontal, 9).padding(.vertical, 5).background(
              .orange.opacity(0.1), in: Capsule())
          }
          ForEach(
            viewModel.researchProviderErrors.keys.sorted(by: { $0.rawValue < $1.rawValue }),
            id: \.self
          ) { provider in
            let message =
              viewModel.researchProviderErrors[provider]?.errorDescription ?? tr("search.failed")
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              Text("\(provider.displayName): \(message)").lineLimit(1)
              Button(tr("common.retry")) { beginSearch() }.buttonStyle(.link)
            }.padding(.horizontal, 9).padding(.vertical, 5).background(
              .orange.opacity(0.1), in: Capsule())
          }
        }.padding(.horizontal, 16).padding(.top, 8)
      }
    }
    if !limitedProviders.isEmpty {
      DisclosureGroup(isExpanded: $showLimitedSourceNotices) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(limitedProviders, id: \.self) { provider in
              HStack(spacing: 6) {
                Text(viewModel.providerErrors[provider]?.errorDescription ?? provider.displayName)
                  .lineLimit(1)
                if let url = limitedSearchURL(provider) {
                  Button(tr("provider.openOfficialSearch")) { DesktopPlatform.shared.open(url) }
                    .buttonStyle(.link)
                }
              }
              .font(.caption)
              .padding(.horizontal, 9).padding(.vertical, 5)
              .background(.quaternary.opacity(0.55), in: Capsule())
            }
          }
        }
      } label: {
        Label(
          tr("provider.limitedSourcesSummary", limitedProviders.count), systemImage: "info.circle"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16).padding(.top, 5)
    }
    HStack {
      Text(viewModel.statusText).foregroundStyle(.secondary)
      Spacer()
      Text(tr("common.showingCount", displayedResultCount)).foregroundStyle(.secondary)
    }
    .font(.caption).padding(.horizontal, 16).padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(tr("accessibility.searchResults", displayedResultCount))
  }

  private var isEmptyResult: Bool {
    switch viewModel.searchScope {
    case .media: viewModel.filteredAssets.isEmpty
    case .research: viewModel.filteredResearchRecords.isEmpty
    case .all: viewModel.filteredAssets.isEmpty && viewModel.filteredResearchRecords.isEmpty
    }
  }

  private var displayedResultCount: Int {
    switch viewModel.searchScope {
    case .media: viewModel.filteredAssets.count
    case .research: viewModel.filteredResearchRecords.count
    case .all: viewModel.filteredAssets.count + viewModel.filteredResearchRecords.count
    }
  }

  @ViewBuilder private var selectionBar: some View {
    HStack(spacing: 12) {
      Button(tr("selection.selectAllVisible")) {
        selection.selectVisible(viewModel.filteredAssets)
      }.disabled(viewModel.filteredAssets.isEmpty)
      if selection.count > 0 {
        Text(tr("selection.count", selection.count)).fontWeight(.semibold)
        Button(tr("selection.downloadSelected")) { downloadSelected() }
          .buttonStyle(.borderedProminent)
        Menu(tr("selection.addToProject")) {
          if let current = viewModel.currentProjectID,
            let project = store.projects.first(where: { $0.id == current })
          {
            Button(project.name) { addSelection(to: current) }
            Divider()
          }
          ForEach(store.projects.filter { $0.id != viewModel.currentProjectID }) { project in
            Button(project.name) { addSelection(to: project.id) }
          }
          Divider()
          Button(tr("project.new")) { showNewProject = true }
        }
        Button(tr("selection.copySourceInfo")) {
          DesktopPlatform.shared.copy(
            AttributionFormatter.sources(for: selectedAssets))
        }
        Button(tr("selection.clear")) { selection.clear() }
      }
      Spacer()
    }
    .controlSize(.small).padding(.horizontal, 16).padding(.vertical, 7)
    .background(.quaternary.opacity(selection.count > 0 ? 0.5 : 0.2))
  }

  private func shouldOfferDirectSearch(_ provider: ProviderID) -> Bool {
    guard provider == .pexels || provider == .pixabay,
      viewModel.providerModes[provider] == .officialAPI,
      let error = viewModel.providerErrors[provider]
    else { return false }
    if case .rateLimited = error { return true }
    return false
  }

  private func shouldOfferAPIKey(_ provider: ProviderID) -> Bool {
    guard provider == .pexels || provider == .pixabay,
      viewModel.providerModes[provider] == .directSearch,
      let error = viewModel.providerErrors[provider]
    else { return false }
    if case .temporarilyBlocked = error { return true }
    if case .rateLimited = error { return true }
    return false
  }

  private func limitedSearchURL(_ provider: ProviderID) -> URL? {
    guard let error = viewModel.providerErrors[provider],
      case .limitedMode(_, let url) = error
    else { return nil }
    return url
  }

  private func accessRestrictedSearchURL(_ provider: ProviderID) -> URL? {
    guard let error = viewModel.providerErrors[provider],
      case .accessRestricted = error
    else { return nil }
    return ProviderPolicy.officialSearchURL(for: provider, query: viewModel.query)
  }

  private var selectedAssets: [MediaAsset] {
    viewModel.filteredAssets.filter(selection.contains)
  }

  private func downloadSelected() {
    let projectName = viewModel.currentProjectID.flatMap { id in
      store.projects.first { $0.id == id }?.name
    }
    for asset in selectedAssets where asset.downloadable {
      downloads.start(
        asset: asset, projectID: viewModel.currentProjectID, projectName: projectName,
        segmentIndex: nil)
    }
  }

  private func addSelection(to projectID: UUID) {
    for asset in selectedAssets { store.addFavorite(asset: asset, projectID: projectID) }
    viewModel.currentProjectID = projectID
  }

  private func createProjectAndAddSelection() {
    let project = store.addProject(name: newProjectName)
    addSelection(to: project.id)
    newProjectName = ""
    showNewProject = false
  }

  private var yearFromBinding: Binding<String> {
    Binding(
      get: { viewModel.yearFrom.map(String.init) ?? "" },
      set: { viewModel.yearFrom = Int($0.filter(\.isNumber)) })
  }

  private var yearToBinding: Binding<String> {
    Binding(
      get: { viewModel.yearTo.map(String.init) ?? "" },
      set: { viewModel.yearTo = Int($0.filter(\.isNumber)) })
  }

  private var researchYearFromBinding: Binding<String> {
    Binding(
      get: { viewModel.researchYearFrom.map(String.init) ?? "" },
      set: { viewModel.researchYearFrom = Int($0.filter(\.isNumber)) })
  }

  private var researchYearToBinding: Binding<String> {
    Binding(
      get: { viewModel.researchYearTo.map(String.init) ?? "" },
      set: { viewModel.researchYearTo = Int($0.filter(\.isNumber)) })
  }

  private func beginSearch() {
    viewModel.prepareKeywords(interfaceLanguage: localization.language)
    if KeywordEngine.containsChinese(viewModel.query) {
      pendingTranslation = viewModel.query
      if translationConfiguration == nil {
        translationConfiguration = TranslationSession.Configuration(
          source: Locale.Language(identifier: "zh-Hans"),
          target: Locale.Language(identifier: "en"))
      } else {
        translationConfiguration?.invalidate()
      }
    } else {
      viewModel.search()
    }
  }

  private func saveCurrentSearch() {
    store.addSavedSearch(viewModel.savedSearch(named: savedSearchName))
    showSaveSearch = false
  }

  private func useHistory(_ history: SearchHistoryRecord) {
    viewModel.query = history.originalQuery
    let restored =
      history.keywordDetails
      ?? history.keywords.map {
        SearchKeyword(
          text: $0,
          language: MultilingualQueryEngine.detectLanguage(
            in: $0, fallback: localization.language),
          origin: .userAdded, priority: 99)
      }
    viewModel.restoreKeywords(restored, interfaceLanguage: localization.language)
    viewModel.currentProjectID = history.projectID
    showHistory = false
    viewModel.search()
  }

  private var visibleKeywordIndices: [Int] {
    guard !showAllSearchLanguages else { return Array(viewModel.keywords.indices) }
    return viewModel.keywords.indices.filter { index in
      let keyword = viewModel.keywords[index]
      return keyword.origin == .input || keyword.language == .english
    }
  }
}

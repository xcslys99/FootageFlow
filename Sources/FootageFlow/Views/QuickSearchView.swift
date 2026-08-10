import SwiftUI
import Translation

struct QuickSearchView: View {
  var onManageSources: () -> Void = {}
  @EnvironmentObject private var viewModel: SearchViewModel
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var translationConfiguration: TranslationSession.Configuration?
  @State private var pendingTranslation = ""
  @State private var showHistory = false

  private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      searchHeader
      Divider()
      if viewModel.isSearching { ProgressView().progressViewStyle(.linear) }
      statusArea
      if !viewModel.isSearching && !viewModel.query.isEmpty && viewModel.filteredAssets.isEmpty {
        ContentUnavailableView(
          tr("search.emptyTitle"), systemImage: "film.stack",
          description: Text(tr("search.emptyDescription"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(viewModel.filteredAssets) { asset in
              MediaAssetCard(asset: asset, projectID: viewModel.currentProjectID, segmentIndex: nil)
              { PreviewWindowManager.shared.show($0) }
            }
          }
          .padding(16)
        }
      }
    }
    .navigationTitle(tr("nav.quickSearch"))
    .toolbar {
      ToolbarItemGroup {
        Button {
          showHistory = true
        } label: {
          Label(tr("search.history"), systemImage: "clock.arrow.circlepath")
        }
        Button {
          viewModel.search(forceRefresh: true)
        } label: {
          Label(tr("search.refresh"), systemImage: "arrow.clockwise")
        }.disabled(viewModel.isSearching || viewModel.keywords.isEmpty)
      }
    }
    .sheet(isPresented: $showHistory) { SearchHistoryView(onUse: useHistory) }
    .onAppear {
      viewModel.selectedProviders = AppSettings.enabledProviders
      viewModel.refreshProviderConfiguration()
    }
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
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
        TextField(tr("search.placeholder"), text: $viewModel.query)
          .textFieldStyle(.plain).font(.title3)
          .onSubmit { beginSearch() }
        if viewModel.isSearching {
          Button(tr("common.stop")) { viewModel.stop() }.buttonStyle(.bordered)
        } else {
          Button(tr("search.button")) { beginSearch() }.buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
      }
      .padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

      HStack(alignment: .top) {
        Text(tr("search.currentKeywords")).foregroundStyle(.secondary).padding(.top, 4)
        VStack(alignment: .leading, spacing: 5) {
          ForEach($viewModel.keywords) { $keyword in
            HStack(spacing: 6) {
              Toggle("", isOn: $keyword.isEnabled).labelsHidden()
              TextField(tr("search.keywordPlaceholder"), text: $keyword.text).textFieldStyle(
                .roundedBorder)
              Button {
                viewModel.removeKeyword(keyword.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
              }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
          }
          Button {
            viewModel.addKeyword()
          } label: {
            Label(tr("search.addKeyword"), systemImage: "plus")
          }.buttonStyle(.plain)
        }
      }
      filters
      providerStatusRow
    }
    .padding(16)
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker(tr("filter.type"), selection: $viewModel.mediaType) {
          ForEach(MediaType.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Picker(tr("filter.orientation"), selection: $viewModel.orientation) {
          ForEach(AssetOrientation.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Picker(tr("filter.resolution"), selection: $viewModel.resolution) {
          ForEach(ResolutionFilter.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 165)
        Picker(tr("filter.duration"), selection: $viewModel.duration) {
          ForEach(DurationFilter.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 160)
        Picker(tr("filter.sort"), selection: $viewModel.sort) {
          ForEach(SearchSort.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 150)
        Spacer()
        Picker(tr("common.project"), selection: $viewModel.currentProjectID) {
          Text(tr("common.uncategorized")).tag(Optional<UUID>.none)
          ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
        }.id(localization.language).frame(width: 210)
      }
      HStack(spacing: 12) {
        Text(tr("filter.source")).foregroundStyle(.secondary)
        ForEach(ProviderID.allCases) { provider in
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
          ).toggleStyle(.checkbox)
        }
        Divider().frame(height: 18)
        Picker(tr("filter.license"), selection: $viewModel.licenseFilter) {
          ForEach(LicenseFilter.allCases) { Text($0.label).tag($0) }
        }.id(localization.language).frame(width: 180)
        Button(tr("settings.manageSources"), systemImage: "slider.horizontal.3") {
          onManageSources()
        }.buttonStyle(.link)
      }
    }
  }

  private var providerStatusRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ProviderID.allCases.filter { viewModel.selectedProviders.contains($0) }) {
          provider in
          let state = viewModel.providerStates[provider]?.availability ?? .available
          HStack(spacing: 5) {
            Circle().fill(providerColor(state)).frame(width: 7, height: 7)
            Text(provider.displayName)
            if let count = viewModel.providerCounts[provider] {
              Text("\(count)").foregroundStyle(.secondary)
            }
          }
          .font(.caption)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(.quaternary.opacity(0.55), in: Capsule())
          .help(
            "\(viewModel.providerModes[provider]?.label ?? "") · \(state.label)"
              .trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
        }
      }
    }
  }

  private func providerColor(_ state: ProviderAvailability) -> Color {
    switch state {
    case .available, .apiConnected: .green
    case .bestEffort: .blue
    case .authenticationRequired: .orange
    case .rateLimited, .temporarilyBlocked: .yellow
    case .unavailable: .red
    case .disabled: .secondary
    }
  }

  @ViewBuilder private var statusArea: some View {
    if !viewModel.providerErrors.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(
            viewModel.providerErrors.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self
          ) { provider in
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              Text(viewModel.providerErrors[provider]?.errorDescription ?? tr("search.failed"))
                .lineLimit(1)
              Button(tr("common.retry")) { viewModel.search(only: provider) }.buttonStyle(.link)
              if shouldOfferDirectSearch(provider) {
                Button(tr("provider.tryDirectSearch")) { viewModel.tryDirectSearch(provider) }
                  .buttonStyle(.link)
              }
              if shouldOfferAPIKey(provider) {
                Button(tr("settings.addAPIKey")) { onManageSources() }.buttonStyle(.link)
              }
            }.padding(.horizontal, 9).padding(.vertical, 5).background(
              .orange.opacity(0.1), in: Capsule())
          }
        }.padding(.horizontal, 16).padding(.top, 8)
      }
    }
    HStack {
      Text(viewModel.statusText).foregroundStyle(.secondary)
      Spacer()
      Text(tr("common.showingCount", viewModel.filteredAssets.count)).foregroundStyle(.secondary)
    }
    .font(.caption).padding(.horizontal, 16).padding(.vertical, 8)
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

  private func beginSearch() {
    viewModel.prepareKeywords()
    if KeywordEngine.containsChinese(viewModel.query) {
      pendingTranslation = viewModel.query
      if translationConfiguration == nil {
        translationConfiguration = TranslationSession.Configuration(
          source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en"))
      } else {
        translationConfiguration?.invalidate()
      }
    } else {
      viewModel.search()
    }
  }

  private func useHistory(_ history: SearchHistoryRecord) {
    viewModel.query = history.originalQuery
    viewModel.keywords = history.keywords.map { SearchKeyword(text: $0) }
    viewModel.currentProjectID = history.projectID
    showHistory = false
    viewModel.search()
  }
}

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case workspace, quickSearch, linkDownloader, scriptSearch, projects, favorites, downloads,
    feedback, settings
  var id: String { rawValue }
  var label: String {
    switch self {
    case .workspace: tr("nav.workspace")
    case .quickSearch: tr("nav.quickSearch")
    case .linkDownloader: tr("nav.linkDownloader")
    case .scriptSearch: tr("nav.scriptSearch")
    case .projects: tr("nav.projects")
    case .favorites: tr("nav.favorites")
    case .downloads: tr("nav.downloads")
    case .feedback: tr("nav.feedback")
    case .settings: tr("nav.settings")
    }
  }
  var icon: String {
    switch self {
    case .workspace: "square.grid.2x2"
    case .quickSearch: "magnifyingglass"
    case .linkDownloader: "link"
    case .scriptSearch: "doc.text.magnifyingglass"
    case .projects: "folder"
    case .favorites: "heart"
    case .downloads: "arrow.down.circle"
    case .feedback: "bubble.left.and.bubble.right"
    case .settings: "gearshape"
    }
  }
}

struct RootView: View {
  @State private var selection: AppSection? = .quickSearch
  @EnvironmentObject private var localization: LocalizationManager
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var updates: AppUpdateController
  @EnvironmentObject private var search: SearchViewModel
  @EnvironmentObject private var workspace: WorkspaceCoordinator

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $selection) { section in
        Label(section.label, systemImage: section.icon).tag(section)
      }
      .navigationTitle("FootageFlow")
      .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } detail: {
      switch selection ?? .quickSearch {
      case .workspace:
        WorkspaceHomeView(
          onOpenSection: { selection = $0 },
          onRunSavedSearch: { saved in
            search.apply(savedSearch: saved)
            selection = .quickSearch
            search.search()
          })
      case .quickSearch: QuickSearchView { selection = .settings }
      case .linkDownloader: LinkDownloaderView { selection = .downloads }
      case .scriptSearch: ScriptSearchView()
      case .projects:
        ProjectsView { record in
          search.findRelatedMedia(record)
          selection = .quickSearch
        }
      case .favorites: FavoritesView()
      case .downloads: DownloadsView()
      case .feedback: FeedbackView()
      case .settings: SettingsView()
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          ForEach(AppLanguage.allCases) { language in
            Button {
              localization.setLanguage(language)
            } label: {
              HStack {
                Text(language.displayName)
                if localization.language == language { Image(systemName: "checkmark") }
              }
            }
          }
        } label: {
          Text("🌐 \(localization.language.displayName)")
            .fontWeight(.semibold)
        }
        .help(tr("language.menu"))
      }
    }
    .task { await updates.checkAtLaunch() }
    .onChange(of: workspace.requestedCommand) { _, command in
      guard let command else { return }
      switch command {
      case .searchMedia:
        search.searchScope = .media
        selection = .quickSearch
      case .searchResearch:
        search.searchScope = .research
        selection = .quickSearch
      case .searchAll:
        search.searchScope = .all
        selection = .quickSearch
      case .focusSearch:
        selection = .quickSearch
      case .clearSearch:
        search.clearSearch()
        selection = .quickSearch
      case .newProject:
        selection = .projects
      case .openProjects, .openResearchNotes, .openRightsAudit, .generateCredits, .exportProject,
        .findDuplicates, .generateContactSheet:
        selection = .projects
      case .openFavorites: selection = .favorites
      case .openDownloads: selection = .downloads
      case .openHistory: selection = .quickSearch
      case .openSavedSearches, .openSmartCollections, .openProviderHealth:
        selection = .workspace
      case .openSettings: selection = .settings
      case .checkForUpdates:
        selection = .settings
        Task { await updates.checkManually() }
      case .retryFailedDownloads:
        selection = .downloads
      case .commandPalette, .globalSearch:
        break
      }
      workspace.complete(command)
    }
    .sheet(isPresented: $workspace.isCommandPalettePresented) {
      WorkspaceCommandPalette { command in workspace.perform(command) }
    }
    .sheet(isPresented: $workspace.isGlobalSearchPresented) {
      WorkspaceGlobalSearch { entry in openWorkspaceEntry(entry) }
    }
    .sheet(item: $updates.availableRelease) { release in
      UpdateAvailableView(
        release: release, notNow: updates.notNow, viewUpdate: updates.viewUpdate)
    }
  }

  private func openWorkspaceEntry(_ entry: WorkspaceSearchEntry) {
    switch entry.kind {
    case .project, .researchReference, .researchNote:
      selection = .projects
    case .media, .favorite:
      selection = .favorites
    case .download:
      selection = .downloads
    case .localFile:
      if let path = entry.localPath { DesktopPlatform.shared.reveal(URL(fileURLWithPath: path)) }
    case .searchHistory:
      search.query = entry.title
      search.prepareKeywords(interfaceLanguage: localization.language)
      selection = .quickSearch
    case .savedSearch:
      if let id = UUID(uuidString: entry.id.replacingOccurrences(of: "savedSearch:", with: "")),
        let saved = store.savedSearches.first(where: { $0.id == id })
      {
        search.apply(savedSearch: saved)
        search.search()
      }
      selection = .quickSearch
    }
  }
}

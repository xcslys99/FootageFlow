import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case quickSearch, linkDownloader, scriptSearch, projects, favorites, downloads, feedback, settings
  var id: String { rawValue }
  var label: String {
    switch self {
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
  @EnvironmentObject private var updates: AppUpdateController

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $selection) { section in
        Label(section.label, systemImage: section.icon).tag(section)
      }
      .navigationTitle("FootageFlow")
      .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    } detail: {
      switch selection ?? .quickSearch {
      case .quickSearch: QuickSearchView { selection = .settings }
      case .linkDownloader: LinkDownloaderView { selection = .downloads }
      case .scriptSearch: ScriptSearchView()
      case .projects: ProjectsView()
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
    .sheet(item: $updates.availableRelease) { release in
      UpdateAvailableView(
        release: release, remindLater: updates.remindLater, viewUpdate: updates.viewUpdate)
    }
  }
}

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case quickSearch, scriptSearch, projects, favorites, downloads, settings
  var id: String { rawValue }
  var label: String {
    switch self {
    case .quickSearch: tr("nav.quickSearch")
    case .scriptSearch: tr("nav.scriptSearch")
    case .projects: tr("nav.projects")
    case .favorites: tr("nav.favorites")
    case .downloads: tr("nav.downloads")
    case .settings: tr("nav.settings")
    }
  }
  var icon: String {
    switch self {
    case .quickSearch: "magnifyingglass"
    case .scriptSearch: "doc.text.magnifyingglass"
    case .projects: "folder"
    case .favorites: "heart"
    case .downloads: "arrow.down.circle"
    case .settings: "gearshape"
    }
  }
}

struct RootView: View {
  @State private var selection: AppSection? = .quickSearch
  @EnvironmentObject private var localization: LocalizationManager

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
      case .scriptSearch: ScriptSearchView()
      case .projects: ProjectsView()
      case .favorites: FavoritesView()
      case .downloads: DownloadsView()
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
  }
}

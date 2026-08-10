import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case quickSearch, scriptSearch, projects, favorites, downloads, settings
    var id: String { rawValue }
    var label: String {
        switch self { case .quickSearch: "快速搜索"; case .scriptSearch: "文稿搜素材"; case .projects: "我的项目"; case .favorites: "收藏"; case .downloads: "下载记录"; case .settings: "设置" }
    }
    var icon: String {
        switch self { case .quickSearch: "magnifyingglass"; case .scriptSearch: "doc.text.magnifyingglass"; case .projects: "folder"; case .favorites: "heart"; case .downloads: "arrow.down.circle"; case .settings: "gearshape" }
    }
}

struct RootView: View {
    @State private var selection: AppSection? = .quickSearch

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.icon).tag(section)
            }
            .navigationTitle("FootageFlow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .quickSearch {
            case .quickSearch: QuickSearchView()
            case .scriptSearch: ScriptSearchView()
            case .projects: ProjectsView()
            case .favorites: FavoritesView()
            case .downloads: DownloadsView()
            case .settings: SettingsView()
            }
        }
    }
}

import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: DataStore
    @State private var selectedProjectID: UUID?
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]
    private var items: [SavedAssetRecord] { selectedProjectID == nil ? store.favorites : store.favorites.filter { $0.projectID == selectedProjectID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("收藏").font(.largeTitle.bold()); Spacer(); Picker("项目", selection: $selectedProjectID) { Text("全部项目").tag(Optional<UUID>.none); ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) } }.frame(width: 220) }.padding()
            Divider()
            if items.isEmpty { ContentUnavailableView("还没有收藏", systemImage: "heart", description: Text("搜索素材后点击心形按钮即可收藏")) }
            else {
                ScrollView { LazyVGrid(columns: columns, spacing: 14) { ForEach(items) { saved in MediaAssetCard(asset: saved.asset, projectID: saved.projectID, segmentIndex: saved.segmentIndex) { PreviewWindowManager.shared.show($0) } } }.padding() }
            }
        }
    }
}

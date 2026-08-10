import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedProjectID: UUID?
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]
    private var items: [SavedAssetRecord] { selectedProjectID == nil ? store.favorites : store.favorites.filter { $0.projectID == selectedProjectID } }

    var body: some View {
        let _ = localization.language
        VStack(spacing: 0) {
            HStack { Text(tr("nav.favorites")).font(.largeTitle.bold()); Spacer(); Picker(tr("common.project"), selection: $selectedProjectID) { Text(tr("project.all")).tag(Optional<UUID>.none); ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) } }.id(localization.language).frame(width: 220) }.padding()
            Divider()
            if items.isEmpty { ContentUnavailableView(tr("favorites.empty"), systemImage: "heart", description: Text(tr("favorites.emptyDescription"))) }
            else {
                ScrollView { LazyVGrid(columns: columns, spacing: 14) { ForEach(items) { saved in MediaAssetCard(asset: saved.asset, projectID: saved.projectID, segmentIndex: saved.segmentIndex) { PreviewWindowManager.shared.show($0) } } }.padding() }
            }
        }
    }
}

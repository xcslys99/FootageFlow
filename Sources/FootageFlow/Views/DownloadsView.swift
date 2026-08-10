import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var localization: LocalizationManager
    @State private var deleteTarget: DownloadRecord?

    var body: some View {
        let _ = localization.language
        VStack(spacing: 0) {
            HStack { Text(tr("download.title")).font(.largeTitle.bold()); Spacer(); Text(tr("common.itemsCount", store.downloads.count)).foregroundStyle(.secondary) }.padding()
            Divider()
            if store.downloads.isEmpty { ContentUnavailableView(tr("download.empty"), systemImage: "arrow.down.circle", description: Text(tr("download.emptyDescription"))) }
            else {
                List(store.downloads) { record in
                    HStack(spacing: 12) {
                        AsyncImage(url: URLValidator.remote(record.thumbnailURL)) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }.frame(width: 110, height: 64).clipped().cornerRadius(6)
                        VStack(alignment: .leading, spacing: 4) { Text(record.fileName).font(.headline).lineLimit(1); Text("\(ProviderID(rawValue: record.providerRaw)?.displayName ?? record.providerRaw) · \(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary); Text(record.localPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                        Spacer()
                        Button(tr("download.revealFinder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.localPath)]) }
                        Button(tr("download.openFile")) { NSWorkspace.shared.open(URL(fileURLWithPath: record.localPath)) }
                        Button(tr("media.openSource")) { if let url = URLValidator.remote(record.sourcePageURL) { NSWorkspace.shared.open(url) } }
                        Menu { Button(tr("download.removeRecord")) { store.deleteDownloadRecord(id: record.id) }; Button(tr("download.deleteLocal"), role: .destructive) { deleteTarget = record } } label: { Image(systemName: "ellipsis.circle") }
                    }.padding(.vertical, 5)
                }
            }
        }
        .alert(tr("download.deleteConfirmTitle"), isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button(tr("common.cancel"), role: .cancel) { deleteTarget = nil }
            Button(tr("download.deleteLocal"), role: .destructive) { deleteLocal() }
        } message: { Text(tr("download.deleteConfirmBody")) }
    }

    private func deleteLocal() {
        guard let record = deleteTarget else { return }
        let url = URL(fileURLWithPath: record.localPath); let base = url.deletingPathExtension()
        for target in [url, base.appendingPathExtension("source.txt"), base.appendingPathExtension("source.json")] { try? FileManager.default.removeItem(at: target) }
        store.deleteDownloadRecord(id: record.id); deleteTarget = nil
    }
}

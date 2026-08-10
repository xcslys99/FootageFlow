import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var deleteTarget: DownloadRecord?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("下载记录").font(.largeTitle.bold()); Spacer(); Text("共 \(store.downloads.count) 条").foregroundStyle(.secondary) }.padding()
            Divider()
            if store.downloads.isEmpty { ContentUnavailableView("暂无下载记录", systemImage: "arrow.down.circle", description: Text("允许下载的素材会在这里显示")) }
            else {
                List(store.downloads) { record in
                    HStack(spacing: 12) {
                        AsyncImage(url: URLValidator.remote(record.thumbnailURL)) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }.frame(width: 110, height: 64).clipped().cornerRadius(6)
                        VStack(alignment: .leading, spacing: 4) { Text(record.fileName).font(.headline).lineLimit(1); Text("\(ProviderID(rawValue: record.providerRaw)?.displayName ?? record.providerRaw) · \(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary); Text(record.localPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                        Spacer()
                        Button("在Finder中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.localPath)]) }
                        Button("打开文件") { NSWorkspace.shared.open(URL(fileURLWithPath: record.localPath)) }
                        Button("打开来源") { if let url = URLValidator.remote(record.sourcePageURL) { NSWorkspace.shared.open(url) } }
                        Menu { Button("仅删除记录") { store.deleteDownloadRecord(id: record.id) }; Button("删除本地文件…", role: .destructive) { deleteTarget = record } } label: { Image(systemName: "ellipsis.circle") }
                    }.padding(.vertical, 5)
                }
            }
        }
        .alert("确认删除本地素材？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除本地文件", role: .destructive) { deleteLocal() }
        } message: { Text("将删除素材文件及同名 .source.txt/.source.json，此操作不可撤销。") }
    }

    private func deleteLocal() {
        guard let record = deleteTarget else { return }
        let url = URL(fileURLWithPath: record.localPath); let base = url.deletingPathExtension()
        for target in [url, base.appendingPathExtension("source.txt"), base.appendingPathExtension("source.json")] { try? FileManager.default.removeItem(at: target) }
        store.deleteDownloadRecord(id: record.id); deleteTarget = nil
    }
}

import SwiftUI

struct DownloadsView: View {
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var localization: LocalizationManager
  @State private var deleteTarget: DownloadRecord?
  @State private var deletionError: String?

  private var currentItems: [DownloadProgress] {
    downloads.states.values
      .filter { $0.status != .completed }
      .sorted {
        let order: [DownloadStatus: Int] = [
          .downloading: 0, .waiting: 1, .failed: 2, .cancelled: 3, .completed: 4,
        ]
        return (order[$0.status] ?? 9, $0.asset.title) < (order[$1.status] ?? 9, $1.asset.title)
      }
  }

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      HStack {
        Text(tr("download.title")).font(.largeTitle.bold())
        Spacer()
        if currentItems.contains(where: { $0.status == .failed || $0.status == .cancelled }) {
          Button(tr("download.retryFailed")) { downloads.retryFailed() }
        }
        Text(tr("common.itemsCount", currentItems.count + store.downloads.count)).foregroundStyle(
          .secondary)
      }.padding()
      Divider()
      if currentItems.isEmpty, store.downloads.isEmpty {
        ContentUnavailableView(
          tr("download.empty"), systemImage: "arrow.down.circle",
          description: Text(tr("download.emptyDescription")))
      } else {
        List {
          if !currentItems.isEmpty {
            Section(tr("download.current")) {
              ForEach(currentItems) { item in currentRow(item) }
            }
          }
          if !store.downloads.isEmpty {
            Section(tr("download.completedSection")) {
              ForEach(store.downloads) { record in completedRow(record) }
            }
          }
        }
      }
    }
    .alert(
      tr("download.deleteConfirmTitle"),
      isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    ) {
      Button(tr("common.cancel"), role: .cancel) { deleteTarget = nil }
      Button(tr("download.deleteLocal"), role: .destructive) { deleteLocal() }
    } message: {
      Text(tr("download.deleteConfirmBody"))
    }
    .alert(
      tr("download.deleteFailedTitle"),
      isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
    ) {
      Button(tr("common.close")) { deletionError = nil }
    } message: {
      Text(deletionError ?? "")
    }
  }

  private func currentRow(_ item: DownloadProgress) -> some View {
    HStack(spacing: 12) {
      RemoteThumbnailView(
        candidates: item.asset.effectiveThumbnailCandidates, provider: item.asset.provider,
        fallbackSystemImage: "arrow.down.circle"
      )
      .frame(width: 110, height: 64).clipped().cornerRadius(6)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(item.asset.title).font(.headline).lineLimit(1)
          Text(item.statusLabel).font(.caption.bold()).foregroundStyle(statusColor(item.status))
        }
        Text(
          [item.asset.sourceDisplayName, item.projectName ?? tr("common.uncategorized")]
            .joined(
              separator: " · ")
        )
        .font(.caption).foregroundStyle(.secondary)
        if item.status == .downloading || item.status == .waiting {
          ProgressView(value: item.progress).frame(maxWidth: 360)
        }
        HStack(spacing: 8) {
          Text(item.message)
          if let speed = item.speedText { Text("· \(speed)") }
        }.font(.caption2).foregroundStyle(item.status == .failed ? .red : .secondary)
        if let summary = item.workflowSummary {
          Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        if let destination = item.destination {
          Text(tr("download.saveLocation", destination.path)).font(.caption2).foregroundStyle(
            .tertiary
          ).lineLimit(1)
        }
      }
      Spacer()
      if item.status == .downloading || item.status == .waiting {
        Button(tr("common.cancel")) { downloads.cancel(stableID: item.id) }
      } else {
        Button(tr("common.retry")) { downloads.retry(stableID: item.id) }
        Button(tr("download.removeRecord")) { downloads.removeState(stableID: item.id) }
      }
      if let destination = item.destination {
        Button(tr("download.openFolder")) {
          DesktopPlatform.shared.open(destination.deletingLastPathComponent())
        }
      }
      Button(tr("media.openSource")) { DesktopPlatform.shared.open(item.asset.sourcePageURL) }
    }.padding(.vertical, 5)
  }

  private func completedRow(_ record: DownloadRecord) -> some View {
    HStack(spacing: 12) {
      RemoteThumbnailView(
        candidates: [URLValidator.remote(record.thumbnailURL)].compactMap { $0 },
        provider: ProviderID(rawValue: record.providerRaw), fallbackSystemImage: "photo"
      )
      .frame(width: 110, height: 64).clipped().cornerRadius(6)
      VStack(alignment: .leading, spacing: 4) {
        Text(record.fileName).font(.headline).lineLimit(1)
        Text(
          "\(record.sourceName?.nilIfEmpty ?? ProviderID(rawValue: record.providerRaw)?.displayName ?? record.providerRaw) · \(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .font(.caption).foregroundStyle(.secondary)
        if let summary = record.workflowSummary {
          Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        Text(record.localPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
      }
      Spacer()
      Button(tr("download.revealFinder")) {
        DesktopPlatform.shared.reveal(URL(fileURLWithPath: record.localPath))
      }
      Button(tr("download.openFile")) {
        DesktopPlatform.shared.open(URL(fileURLWithPath: record.localPath))
      }
      Button(tr("media.openSource")) {
        if let url = URLValidator.remote(record.sourcePageURL) {
          DesktopPlatform.shared.open(url)
        }
      }
      Menu {
        Button(tr("download.removeRecord")) { store.deleteDownloadRecord(id: record.id) }
        Button(tr("download.deleteLocal"), role: .destructive) { deleteTarget = record }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
    }.padding(.vertical, 5)
  }

  private func statusColor(_ status: DownloadStatus) -> Color {
    switch status {
    case .completed: .green
    case .failed: .red
    case .cancelled: .secondary
    case .waiting: .orange
    case .downloading: .accentColor
    }
  }

  private func deleteLocal() {
    guard let record = deleteTarget else { return }
    let mediaURL = URL(fileURLWithPath: record.localPath)
    let targets = DownloadPathSafety.relatedFiles(for: mediaURL)
    guard targets.allSatisfy({ DownloadPathSafety.isContained($0) }) else {
      deleteTarget = nil
      deletionError = tr("download.deleteUnsafe")
      return
    }
    do {
      for target in targets where FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      store.deleteDownloadRecord(id: record.id)
      deleteTarget = nil
    } catch {
      deleteTarget = nil
      deletionError = tr("deletion.localFileFailed")
    }
  }
}

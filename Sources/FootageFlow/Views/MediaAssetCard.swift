import SwiftUI

struct MediaAssetCard: View {
  let asset: MediaAsset
  let projectID: UUID?
  let segmentIndex: Int?
  var isSelected = false
  var onToggleSelection: ((MediaAsset) -> Void)? = nil
  let onPreview: (MediaAsset) -> Void
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var localization: LocalizationManager

  private var projectName: String? {
    projectID.flatMap { id in store.projects.first { $0.id == id }?.name }
  }
  private var downloadState: DownloadProgress? { downloads.states[asset.stableID] }

  var body: some View {
    let _ = localization.language
    VStack(alignment: .leading, spacing: 9) {
      AsyncImage(url: asset.thumbnailURL) { phase in
        switch phase {
        case .success(let image): image.resizable().scaledToFill()
        case .failure: placeholder(tr("media.thumbnailUnavailable"))
        default:
          ZStack {
            Color.secondary.opacity(0.08)
            ProgressView()
          }
        }
      }
      .frame(height: 150).clipped().background(.quaternary)
      .overlay(alignment: .topLeading) {
        Label(
          asset.sourceDisplayName, systemImage: mediaIcon
        )
        .font(.caption2.bold()).padding(5)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 5)).padding(7)
      }
      .overlay(alignment: .topTrailing) {
        if let onToggleSelection {
          Button {
            onToggleSelection(asset)
          } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
              .font(.title2).symbolRenderingMode(.palette)
              .foregroundStyle(
                isSelected ? Color.white : Color.secondary,
                isSelected ? Color.accentColor : Color.white)
          }
          .buttonStyle(.plain).padding(8).help(tr("selection.select"))
        }
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(asset.title).font(.headline).lineLimit(2).frame(
          minHeight: 38, alignment: .topLeading)
        LabeledContent(
          tr("media.specifications"),
          value: "\(asset.resolutionText) · \(asset.orientation.label)")
        if asset.mediaType == .video {
          LabeledContent(tr("media.duration"), value: asset.durationText)
        }
        LabeledContent(tr("media.license"), value: asset.licenseText)
          .foregroundStyle(asset.licenseStatus == .unknown ? .orange : .secondary)
          .help(
            asset.licenseStatus == .unknown ? tr("media.licenseUnavailable") : asset.licenseText)
        if let creator = asset.creator {
          LabeledContent(tr("media.creator"), value: creator).lineLimit(1)
        }
      }.font(.caption).foregroundStyle(.secondary)
      if let downloadState {
        ProgressView(value: downloadState.progress).help(downloadState.message)
        HStack(spacing: 5) {
          Text(downloadState.message)
          if let speed = downloadState.speedText { Text("· \(speed)") }
        }.font(.caption2).foregroundStyle(downloadState.status == .failed ? .red : .secondary)
      }
      HStack(spacing: 7) {
        if asset.previewURL != nil { Button(tr("media.preview")) { onPreview(asset) } }
        Button {
          store.toggleFavorite(asset: asset, projectID: projectID, segmentIndex: segmentIndex)
        } label: {
          Image(
            systemName: store.isFavorite(asset, projectID: projectID) ? "heart.fill" : "heart")
        }.help(tr("media.favorite"))
        if asset.downloadable {
          if let downloadState,
            downloadState.status == .downloading || downloadState.status == .waiting
          {
            Button(tr("common.cancel")) { downloads.cancel(stableID: asset.stableID) }
          } else if let downloadState,
            downloadState.status == .failed || downloadState.status == .cancelled
          {
            Button(tr("common.retry")) { downloads.retry(stableID: asset.stableID) }
          } else {
            Button(tr("media.download")) {
              downloads.start(
                asset: asset, projectID: projectID, projectName: projectName,
                segmentIndex: segmentIndex)
            }
          }
        }
        Spacer()
        Button(tr("media.openSource")) {
          guard let url = try? URLValidator.remote(asset.sourcePageURL) else { return }
          DesktopPlatform.shared.open(url)
        }
        Menu {
          Button(tr("media.copySource")) {
            DesktopPlatform.shared.copy(AttributionFormatter.source(for: asset))
          }
          Button(tr("media.copyAttribution")) {
            DesktopPlatform.shared.copy(AttributionFormatter.attribution(for: asset))
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }.controlSize(.small)
    }
    .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6), lineWidth: 1))
  }

  private func placeholder(_ text: String) -> some View {
    ZStack {
      Color.secondary.opacity(0.1)
      VStack {
        Image(systemName: mediaIcon)
        Text(text).font(.caption)
      }.foregroundStyle(.secondary)
    }
  }

  private var mediaIcon: String {
    switch asset.mediaType {
    case .video: "film"
    case .image: "photo"
    case .audio: "waveform"
    case .all: "doc"
    }
  }
}

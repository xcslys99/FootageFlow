import SwiftUI

struct MediaAssetCard: View {
    let asset: MediaAsset
    let projectID: UUID?
    let segmentIndex: Int?
    let onPreview: (MediaAsset) -> Void
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var downloads: DownloadManager

    private var projectName: String? { projectID.flatMap { id in store.projects.first { $0.id == id }?.name } }
    private var downloadState: DownloadProgress? { downloads.states[asset.stableID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AsyncImage(url: asset.thumbnailURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: placeholder("缩略图不可用")
                default: ZStack { Color.secondary.opacity(0.08); ProgressView() }
                }
            }
            .frame(height: 150).clipped().background(.quaternary)
            .overlay(alignment: .topLeading) {
                Label(asset.provider.displayName, systemImage: asset.mediaType == .video ? "film" : "photo")
                    .font(.caption2.bold()).padding(5)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 5)).padding(7)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(asset.title).font(.headline).lineLimit(2).frame(minHeight: 38, alignment: .topLeading)
                LabeledContent("规格", value: "\(asset.resolutionText) · \(asset.orientation.label)")
                if asset.mediaType == .video { LabeledContent("时长", value: asset.durationText) }
                LabeledContent("授权", value: asset.licenseText)
                    .foregroundStyle(asset.licenseStatus == .unknown ? .orange : .secondary)
                    .help(asset.licenseStatus == .unknown ? "未能获取明确许可信息，请在使用前查看原始来源。" : asset.licenseText)
                if let creator = asset.creator { LabeledContent("作者", value: creator).lineLimit(1) }
            }.font(.caption).foregroundStyle(.secondary)
            if let downloadState {
                ProgressView(value: downloadState.progress).help(downloadState.message)
                Text(downloadState.message).font(.caption2).foregroundStyle(downloadState.status == .failed ? .red : .secondary)
            }
            HStack(spacing: 7) {
                if asset.previewURL != nil { Button("预览") { onPreview(asset) } }
                Button { store.toggleFavorite(asset: asset, projectID: projectID, segmentIndex: segmentIndex) } label: { Image(systemName: store.isFavorite(asset, projectID: projectID) ? "heart.fill" : "heart") }.help("收藏")
                if asset.downloadable && asset.provider != .youtube {
                    Button("下载") { downloads.start(asset: asset, projectID: projectID, projectName: projectName, segmentIndex: segmentIndex) }
                }
                Spacer()
                Button("打开来源") {
                    guard let url = try? URLValidator.remote(asset.sourcePageURL) else { return }
                    NSWorkspace.shared.open(url)
                }
            }.controlSize(.small)
        }
        .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6), lineWidth: 1))
    }

    private func placeholder(_ text: String) -> some View { ZStack { Color.secondary.opacity(0.1); VStack { Image(systemName: asset.mediaType == .video ? "film" : "photo"); Text(text).font(.caption) }.foregroundStyle(.secondary) } }
}

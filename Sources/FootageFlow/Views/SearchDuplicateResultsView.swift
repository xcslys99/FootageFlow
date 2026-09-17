import SwiftUI

/// Presentation-only grouping. The original ranked and filtered assets remain intact.
struct SearchDuplicateResultsView: View {
  let assets: [MediaAsset]
  let projectID: UUID?
  let selectedIDs: Set<String>
  let onToggleSelection: (MediaAsset) -> Void

  @AppStorage(AppSettings.detectSearchDuplicatesKey) private var detectionEnabled = true
  @AppStorage(AppSettings.collapseDuplicateGroupsKey) private var collapseByDefault = true
  @EnvironmentObject private var localization: LocalizationManager
  @State private var review: SearchDuplicateReview?
  @State private var showAll = false
  @State private var expanded = Set<String>()
  private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]

  private var signature: String {
    "\(detectionEnabled):" + assets.map(\.stableID).joined(separator: "|")
  }

  var body: some View {
    let _ = localization.language
    let indexedAssets = Dictionary(
      assets.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
    VStack(alignment: .leading, spacing: 12) {
      if detectionEnabled, let review, !review.groups.isEmpty {
        HStack {
          Text(tr("duplicate.summary", review.resultCount, review.uniqueCount, review.groups.count))
            .font(.callout).foregroundStyle(.secondary)
            .accessibilityLabel(
              tr("duplicate.summary", review.resultCount, review.uniqueCount, review.groups.count))
          Spacer()
          Picker(tr("duplicate.view"), selection: $showAll) {
            Text(tr("duplicate.grouped")).tag(false)
            Text(tr("duplicate.allResults")).tag(true)
          }
          .pickerStyle(.segmented).frame(width: 240)
        }
      }
      LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
        if detectionEnabled, let review, !showAll, !review.groups.isEmpty {
          ForEach(review.entries) { entry in
            if entry.isGroup {
              groupCard(entry, assetsByID: indexedAssets)
            } else if let asset = indexedAssets[entry.recommendedID] {
              assetCard(asset)
            }
          }
        } else {
          ForEach(assets) { asset in assetCard(asset) }
        }
      }
    }
    .task(id: signature) {
      review = nil
      guard detectionEnabled, assets.count > 1 else { return }
      let snapshot = assets
      let analyzed = await Task.detached(priority: .utility) {
        SearchDuplicateAnalyzer.analyze(snapshot, isCancelled: { Task.isCancelled })
      }.value
      guard !Task.isCancelled else { return }
      review = analyzed
      guard !analyzed.thumbnailCandidateIDs.isEmpty else { return }
      let hashes = await DuplicateThumbnailHashService.shared.hashes(
        for: snapshot, candidateIDs: analyzed.thumbnailCandidateIDs)
      guard !Task.isCancelled, !hashes.isEmpty else { return }
      let visualReview = await Task.detached(priority: .utility) {
        SearchDuplicateAnalyzer.analyze(
          snapshot, thumbnailHashes: hashes,
          isCancelled: { Task.isCancelled })
      }.value
      if !Task.isCancelled { review = visualReview }
    }
    .onAppear { showAll = !collapseByDefault }
    .onChange(of: collapseByDefault) { _, value in showAll = !value }
  }

  @ViewBuilder private func groupCard(
    _ entry: SearchDuplicateEntry, assetsByID: [String: MediaAsset]
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
      } label: {
        HStack {
          Image(systemName: expanded.contains(entry.id) ? "chevron.down" : "chevron.right")
          Text(tr("duplicate.groupTitle", confidenceLabel(entry.confidence), entry.memberIDs.count))
            .font(.subheadline.bold())
          Spacer()
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        tr("duplicate.groupTitle", confidenceLabel(entry.confidence), entry.memberIDs.count)
      )
      .accessibilityValue(
        expanded.contains(entry.id) ? tr("duplicate.expanded") : tr("duplicate.collapsed"))
      if let recommended = assetsByID[entry.recommendedID] {
        Text(tr("duplicate.recommendedVersion"))
          .font(.caption.bold()).foregroundStyle(.secondary)
        assetCard(recommended)
      }
      if expanded.contains(entry.id) {
        ForEach(entry.memberIDs.filter { $0 != entry.recommendedID }, id: \.self) { id in
          if let asset = assetsByID[id] { assetCard(asset) }
        }
      }
    }
    .padding(8)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
  }

  private func confidenceLabel(_ confidence: SearchDuplicateConfidence?) -> String {
    confidence?.label ?? tr("duplicate.possible")
  }

  private func assetCard(_ asset: MediaAsset) -> some View {
    MediaAssetCard(
      asset: asset, projectID: projectID, segmentIndex: nil,
      isSelected: selectedIDs.contains(asset.stableID),
      onToggleSelection: onToggleSelection
    ) { PreviewWindowManager.shared.show($0) }
  }
}

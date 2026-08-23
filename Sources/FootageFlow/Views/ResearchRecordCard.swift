import SwiftUI

struct ResearchRecordCard: View {
  let record: ResearchRecord
  let projectID: UUID?
  let onFindRelatedMedia: (ResearchRecord) -> Void
  let onAddAsMedia: (ResearchRecord) -> Void
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var actionMessage: String?

  var body: some View {
    let _ = localization.language
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        if let thumbnail = record.thumbnailURL {
          RemoteThumbnailView(candidates: [thumbnail], fallbackSystemImage: "book.closed")
            .frame(width: 112, height: 82).clipShape(RoundedRectangle(cornerRadius: 7))
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(record.title).font(.headline).lineLimit(2)
          Text("\(record.source) · \(record.type.label)")
            .font(.caption).foregroundStyle(.secondary)
          if let year = record.year { Text(year).font(.caption).foregroundStyle(.secondary) }
          if let doi = record.doi {
            Text("DOI: \(doi)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          }
          if let qid = record.wikidataQID { Text(qid).font(.caption2).foregroundStyle(.secondary) }
        }
      }
      if let summary = record.summary, !summary.isEmpty {
        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(4)
      }
      if !record.displayAuthors.isEmpty {
        LabeledContent(tr("research.authors"), value: record.displayAuthors)
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
      }
      if let actionMessage { Text(actionMessage).font(.caption2).foregroundStyle(.secondary) }
      HStack(spacing: 8) {
        Button(tr("research.addToNotes")) { addToNotes() }
          .disabled(projectID == nil)
          .help(projectID == nil ? tr("research.selectProject") : tr("research.addToNotes"))
        Button(tr("research.copyCitation")) { DesktopPlatform.shared.copy(record.citationText) }
        Button(tr("research.findRelatedMedia")) { onFindRelatedMedia(record) }
        if ResearchMediaAdapter.asset(for: record) != nil {
          Button(tr("research.addAsMedia")) { onAddAsMedia(record) }
        }
        Spacer()
        Button(tr("media.openSource")) { DesktopPlatform.shared.open(record.canonicalURL) }
      }
      .controlSize(.small)
    }
    .padding(12)
    .background(.background, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.6), lineWidth: 1))
  }

  private func addToNotes() {
    guard let projectID else { return }
    let added = store.addResearchReference(
      ResearchReferenceRecord(projectID: projectID, record: record))
    actionMessage = tr(added ? "research.addedToNotes" : "research.alreadyInNotes")
  }
}

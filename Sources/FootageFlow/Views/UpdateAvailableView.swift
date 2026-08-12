import SwiftUI

struct UpdateAvailableView: View {
  let release: AppRelease
  let remindLater: () -> Void
  let viewUpdate: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 42))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 5) {
          Text(tr("update.availableTitle", release.version)).font(.title.bold())
          Text(tr("update.versionComparison", FootageFlowVersion.current, release.version))
            .foregroundStyle(.secondary)
          if let publishedAt = release.publishedAt {
            Text(tr("update.published", publishedAt.formatted(date: .long, time: .omitted)))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Text(release.title).font(.headline)
      Text(tr("update.whatsNew")).font(.title3.bold())
      ScrollView {
        Text(verbatim: release.notes.isEmpty ? tr("update.notesUnavailable") : release.notes)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .frame(minHeight: 180, maxHeight: 360)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      Text(tr("update.noAutomaticInstall"))
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button(tr("update.remindLater"), action: remindLater)
        Button(tr("update.viewUpdate"), action: viewUpdate).buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 460)
    .interactiveDismissDisabled()
  }
}

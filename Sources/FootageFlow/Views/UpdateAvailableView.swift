import SwiftUI

struct UpdateAvailableView: View {
  private enum FocusTarget: Hashable { case notNow, viewUpdate }
  let release: AppRelease
  let notNow: () -> Void
  let viewUpdate: () -> Void
  @FocusState private var focusTarget: FocusTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 42))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(tr("update.availableTitle")).font(.title.bold())
          Text(tr("update.currentVersionValue", FootageFlowVersion.current))
            .foregroundStyle(.secondary)
          Text(tr("update.latestVersionValue", release.version))
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
      .accessibilityLabel(tr("accessibility.updateNotes"))
      Text(tr("update.noAutomaticInstall"))
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button(tr("update.notNow"), action: notNow)
          .focused($focusTarget, equals: .notNow)
          .keyboardShortcut(.cancelAction)
        Button(tr("update.viewUpdate"), action: viewUpdate)
          .buttonStyle(.borderedProminent)
          .focused($focusTarget, equals: .viewUpdate)
          .keyboardShortcut(.defaultAction)
          .accessibilityHint(tr("update.noAutomaticInstall"))
      }
    }
    .padding(24)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 460)
    .interactiveDismissDisabled()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(tr("accessibility.updateDialog"))
    .onAppear { focusTarget = .notNow }
  }
}

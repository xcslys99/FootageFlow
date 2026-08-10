import SwiftUI

struct SearchHistoryView: View {
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @Environment(\.dismiss) private var dismiss
  let onUse: (SearchHistoryRecord) -> Void
  @State private var confirmClear = false

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      HStack {
        Text(tr("search.history")).font(.title2.bold())
        Spacer()
        Button(tr("history.clear")) { confirmClear = true }.disabled(store.history.isEmpty)
        Button(tr("common.close")) { dismiss() }
      }.padding()
      Divider()
      List(store.history) { item in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(item.originalQuery).font(.headline)
            Text(item.keywords.joined(separator: " · ")).font(.caption).foregroundStyle(
              .secondary
            )
            .lineLimit(1)
            Text(
              tr(
                "history.summary",
                item.searchedAt.formatted(date: .abbreviated, time: .shortened),
                item.resultCount)
            ).font(.caption2).foregroundStyle(.tertiary)
          }
          Spacer()
          Button(tr("history.research")) { onUse(item) }
          Button {
            store.deleteHistory(id: item.id)
          } label: {
            Image(systemName: "trash")
          }.buttonStyle(.plain).help(tr("common.delete"))
        }.padding(.vertical, 4)
      }
    }.frame(width: 760, height: 520)
      .alert(tr("history.clearConfirmTitle"), isPresented: $confirmClear) {
        Button(tr("common.cancel"), role: .cancel) {}
        Button(tr("history.clear"), role: .destructive) { store.clearHistory() }
      } message: {
        Text(tr("history.clearConfirmBody"))
      }
  }
}

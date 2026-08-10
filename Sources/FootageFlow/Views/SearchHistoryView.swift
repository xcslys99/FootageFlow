import SwiftUI

struct SearchHistoryView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let onUse: (SearchHistoryRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("搜索历史").font(.title2.bold()); Spacer(); Button("清空") { store.clearHistory() }.disabled(store.history.isEmpty); Button("关闭") { dismiss() } }.padding()
            Divider()
            List(store.history) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(item.originalQuery).font(.headline); Text(item.keywords.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text("\(item.searchedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.resultCount) 条").font(.caption2).foregroundStyle(.tertiary) }
                    Spacer(); Button("重新搜索") { onUse(item) }; Button { store.deleteHistory(id: item.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }.padding(.vertical, 4)
            }
        }.frame(width: 760, height: 520)
    }
}

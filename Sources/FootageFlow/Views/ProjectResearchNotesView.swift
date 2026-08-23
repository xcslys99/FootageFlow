import SwiftUI

struct ProjectResearchNotesView: View {
  let projectID: UUID
  var onFindRelatedMedia: (ResearchRecord) -> Void = { _ in }
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var searchText = ""
  @State private var selectedType: ResearchRecordType?
  @State private var selectedSource = ""
  @State private var sortNewest = true
  @State private var refreshingIDs = Set<UUID>()

  private var records: [ResearchReferenceRecord] {
    store.researchReferences(projectID: projectID).filter { value in
      let matchesText =
        searchText.isEmpty
        || [
          value.record.title, value.record.source, value.myNote, value.tags.joined(separator: " "),
        ].joined(separator: " ").localizedCaseInsensitiveContains(searchText)
      let matchesType = selectedType == nil || value.record.type == selectedType
      let matchesSource = selectedSource.isEmpty || value.record.source == selectedSource
      return matchesText && matchesType && matchesSource
    }.sorted {
      let left = sortNewest ? $0.addedAt : ($0.record.publishedDate ?? .distantPast)
      let right = sortNewest ? $1.addedAt : ($1.record.publishedDate ?? .distantPast)
      return left > right
    }
  }

  private var sources: [String] {
    Array(Set(store.researchReferences(projectID: projectID).map { $0.record.source })).sorted()
  }

  var body: some View {
    let _ = localization.language
    VStack(alignment: .leading, spacing: 9) {
      Text(tr("research.notes")).font(.headline)
      HStack {
        TextField(tr("research.searchNotes"), text: $searchText).textFieldStyle(.roundedBorder)
        Picker(tr("research.type"), selection: $selectedType) {
          Text(tr("common.all")).tag(Optional<ResearchRecordType>.none)
          ForEach(ResearchRecordType.allCases) { Text($0.label).tag(Optional($0)) }
        }.frame(width: 175)
        Picker(tr("research.source"), selection: $selectedSource) {
          Text(tr("common.all")).tag("")
          ForEach(sources, id: \.self) { Text($0).tag($0) }
        }.frame(width: 180)
        Button(sortNewest ? tr("research.sortAdded") : tr("research.sortPublished")) {
          sortNewest.toggle()
        }
      }
      if records.isEmpty {
        Text(tr("research.noNotes")).font(.caption).foregroundStyle(.secondary)
      }
      ForEach(records) { reference in
        noteCard(reference)
      }
    }
  }

  private func noteCard(_ reference: ResearchReferenceRecord) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Text(reference.record.title).font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(reference.record.source) · \(reference.record.type.label)")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let summary = reference.record.summary {
        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
      }
      Text(reference.record.citationText).font(.caption2).foregroundStyle(.secondary).textSelection(
        .enabled)
      TextEditor(text: binding(for: reference, keyPath: \.myNote))
        .font(.caption).frame(minHeight: 58).padding(4)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 6))
      TextField(tr("research.tags"), text: tagsBinding(for: reference)).textFieldStyle(
        .roundedBorder)
      HStack {
        Button(tr("research.copyCitation")) {
          DesktopPlatform.shared.copy(reference.record.citationText)
        }
        Button(tr("research.findRelatedMedia")) { onFindRelatedMedia(reference.record) }
        Button(tr("research.refreshMetadata")) { refresh(reference) }
          .disabled(refreshingIDs.contains(reference.id))
        Spacer()
        Button(tr("media.openSource")) {
          DesktopPlatform.shared.open(reference.record.canonicalURL)
        }
        Button(tr("common.delete"), role: .destructive) {
          store.deleteResearchReference(id: reference.id)
        }
      }.controlSize(.small)
    }
    .padding(10).background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
  }

  private func binding(
    for reference: ResearchReferenceRecord,
    keyPath: WritableKeyPath<ResearchReferenceRecord, String>
  ) -> Binding<String> {
    Binding(
      get: { reference[keyPath: keyPath] },
      set: { value in
        var updated = reference
        updated[keyPath: keyPath] = value
        store.updateResearchReference(updated)
      })
  }

  private func tagsBinding(for reference: ResearchReferenceRecord) -> Binding<String> {
    Binding(
      get: { reference.tags.joined(separator: ", ") },
      set: { value in
        var updated = reference
        updated.tags = value.split(separator: ",").map {
          String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        store.updateResearchReference(updated)
      })
  }

  private func refresh(_ reference: ResearchReferenceRecord) {
    refreshingIDs.insert(reference.id)
    let language = localization.language
    Task {
      defer { refreshingIDs.remove(reference.id) }
      do {
        let refreshed = try await ResearchMetadataRefresher.refresh(
          reference, interfaceLanguage: language)
        store.updateResearchReference(refreshed)
      } catch {
        // Existing notes remain untouched on timeout, rate limiting, or an
        // offline device. The provider error is intentionally not destructive.
      }
    }
  }
}

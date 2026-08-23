import Foundation

/// A local-only in-memory index. It is rebuilt from FootageFlow's existing
/// metadata and never scans arbitrary folders or sends user records to a server.
actor WorkspaceSearchIndex {
  static let shared = WorkspaceSearchIndex()
  private var entries: [WorkspaceSearchEntry] = []
  private var snapshotFingerprint = ""

  func rebuild(snapshot: WorkspaceSearchSnapshot) {
    let fingerprint = fingerprint(for: snapshot)
    guard fingerprint != snapshotFingerprint else { return }
    var values: [WorkspaceSearchEntry] = []
    let projectNames = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) })
    for project in snapshot.projects {
      values.append(
        WorkspaceSearchEntry(
          id: "project:\(project.id.uuidString)", kind: .project, title: project.name,
          detail: scrubSensitiveText(project.script), projectID: project.id, date: project.updatedAt
        ))
    }
    for favorite in snapshot.favorites {
      let kind: WorkspaceItemKind = favorite.projectID == nil ? .favorite : .media
      values.append(
        WorkspaceSearchEntry(
          id: "favorite:\(favorite.id)", kind: kind, title: favorite.title,
          detail: [
            favorite.providerRaw, favorite.licenseName ?? "",
            favorite.projectID.flatMap { projectNames[$0] } ?? "",
          ].filter { !$0.isEmpty }.joined(separator: " · "),
          projectID: favorite.projectID, sourceURL: URL(string: favorite.sourcePageURL),
          date: favorite.savedAt))
    }
    for download in snapshot.downloads {
      values.append(
        WorkspaceSearchEntry(
          id: "download:\(download.id.uuidString)", kind: .download, title: download.title,
          detail: [
            download.providerRaw, download.fileName,
            download.projectID.flatMap { projectNames[$0] } ?? "",
          ].filter { !$0.isEmpty }.joined(separator: " · "),
          projectID: download.projectID, sourceURL: URL(string: download.sourcePageURL),
          localPath: download.localPath, date: download.downloadedAt))
      values.append(
        WorkspaceSearchEntry(
          id: "file:\(download.id.uuidString)", kind: .localFile, title: download.fileName,
          detail: [download.localPath, download.projectID.flatMap { projectNames[$0] } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · "),
          projectID: download.projectID, sourceURL: URL(string: download.sourcePageURL),
          localPath: download.localPath, date: download.downloadedAt,
          searchableText: [
            download.fileName, download.projectID.flatMap { projectNames[$0] } ?? "",
          ]
          .filter { !$0.isEmpty }.joined(separator: " ")))
    }
    for history in snapshot.history {
      values.append(
        WorkspaceSearchEntry(
          id: "history:\(history.id.uuidString)", kind: .searchHistory,
          title: history.originalQuery,
          detail: [
            history.keywords.joined(separator: " · "),
            history.projectID.flatMap { projectNames[$0] } ?? "",
          ]
          .filter { !$0.isEmpty }.joined(separator: " · "), projectID: history.projectID,
          date: history.searchedAt))
    }
    for saved in snapshot.savedSearches {
      values.append(
        WorkspaceSearchEntry(
          id: "savedSearch:\(saved.id.uuidString)", kind: .savedSearch, title: saved.name,
          detail: saved.query, date: saved.updatedAt))
    }
    for reference in snapshot.researchReferences {
      let record = reference.record
      let sourceDetail = [record.source, reference.tags.joined(separator: " ")]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
      let projectDetail = [sourceDetail, projectNames[reference.projectID] ?? ""]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
      values.append(
        WorkspaceSearchEntry(
          id: "reference:\(reference.id.uuidString)", kind: .researchReference, title: record.title,
          detail: projectDetail, projectID: reference.projectID,
          sourceURL: record.canonicalURL, date: reference.updatedAt))
      let note = scrubSensitiveText(reference.myNote)
      if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values.append(
          WorkspaceSearchEntry(
            id: "note:\(reference.id.uuidString)", kind: .researchNote, title: record.title,
            detail: [record.source, note, projectNames[reference.projectID] ?? ""]
              .filter { !$0.isEmpty }
              .joined(separator: " · "), projectID: reference.projectID,
            sourceURL: record.canonicalURL, date: reference.updatedAt))
      }
    }
    entries = values
    snapshotFingerprint = fingerprint
  }

  func search(_ query: String, limit: Int = 80) -> [WorkspaceSearchEntry] {
    let tokens = normalizedTokens(query)
    guard !tokens.isEmpty else {
      return Array(
        entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(limit))
    }
    return entries.compactMap { entry -> (WorkspaceSearchEntry, Int)? in
      let text = normalize(entry.searchableText)
      let title = normalize(entry.title)
      var score = 0
      for token in tokens {
        guard text.contains(token) else { return nil }
        score += title.contains(token) ? 4 : 1
      }
      return (entry, score)
    }
    .sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      return ($0.0.date ?? .distantPast) > ($1.0.date ?? .distantPast)
    }
    .prefix(limit)
    .map(\.0)
  }

  private func normalizedTokens(_ value: String) -> [String] {
    normalize(value).split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
  }

  private func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
  }

  /// Notes and scripts are user-owned content, so we search them locally. A
  /// credential-looking assignment is deliberately excluded from both the
  /// result preview and index; keys never become searchable metadata.
  private func scrubSensitiveText(_ value: String) -> String {
    value.split(whereSeparator: \.isNewline).compactMap { line in
      let text = String(line)
      let lower = text.lowercased()
      let markers = [
        "api_key=", "apikey=", "token=", "authorization:", "password=", "cookie:",
        "x-amz-signature",
      ]
      return markers.contains(where: lower.contains) ? nil : text
    }.joined(separator: " ")
  }

  /// This intentionally fingerprints metadata already held by PersistentStore.
  /// It avoids disk scans and makes ordinary no-change searches effectively free.
  private func fingerprint(for snapshot: WorkspaceSearchSnapshot) -> String {
    [
      snapshot.projects.map { "p:\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
      snapshot.favorites.map { "f:\($0.id):\($0.savedAt.timeIntervalSince1970)" },
      snapshot.downloads.map { "d:\($0.id.uuidString):\($0.downloadedAt.timeIntervalSince1970)" },
      snapshot.history.map { "h:\($0.id.uuidString):\($0.searchedAt.timeIntervalSince1970)" },
      snapshot.savedSearches.map { "s:\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" },
      snapshot.researchReferences.map {
        "r:\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
      },
    ]
    .flatMap { $0 }
    .sorted()
    .joined(separator: "|")
  }
}

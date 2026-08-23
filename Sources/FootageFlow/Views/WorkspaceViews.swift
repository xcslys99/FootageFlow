import SwiftUI

struct WorkspaceHomeView: View {
  let onOpenSection: (AppSection) -> Void
  let onRunSavedSearch: (SavedSearchRecord) -> Void
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @EnvironmentObject private var workspace: WorkspaceCoordinator
  @State private var destination: WorkspaceDestination = .overview

  private enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case overview, savedSearches, collections, providerHealth, shortcuts
    var id: String { rawValue }
    var key: String { "workspace.destination.\(rawValue)" }
  }

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(tr("nav.workspace")).font(.largeTitle.bold())
          Text(tr("workspace.tagline")).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          workspace.perform(.globalSearch)
        } label: {
          Label(tr("workspace.globalSearch"), systemImage: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .accessibilityHint(tr("workspace.globalSearchHint"))
        Button {
          workspace.perform(.commandPalette)
        } label: {
          Label(tr("workspace.commandPalette"), systemImage: "command")
        }
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityHint(tr("workspace.commandPaletteHint"))
      }
      .padding(24)
      Picker(tr("workspace.destination"), selection: $destination) {
        ForEach(WorkspaceDestination.allCases) { item in Text(tr(item.key)).tag(item) }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
      Divider()
      ScrollView {
        Group {
          switch destination {
          case .overview:
            WorkspaceOverview(onOpenSection: onOpenSection, onRunSavedSearch: onRunSavedSearch)
          case .savedSearches:
            SavedSearchesPane(onRun: onRunSavedSearch)
          case .collections:
            SmartCollectionsPane(onOpenSection: onOpenSection)
          case .providerHealth:
            ProviderHealthPane()
          case .shortcuts:
            ShortcutReferencePane()
          }
        }
        .padding(24)
      }
    }
    .onChange(of: workspace.requestedCommand) { _, command in
      guard let command else { return }
      switch command {
      case .openSavedSearches: destination = .savedSearches
      case .openSmartCollections: destination = .collections
      case .openProviderHealth: destination = .providerHealth
      default: return
      }
      workspace.complete(command)
    }
    .navigationTitle(tr("nav.workspace"))
  }
}

private struct WorkspaceOverview: View {
  let onOpenSection: (AppSection) -> Void
  let onRunSavedSearch: (SavedSearchRecord) -> Void
  @EnvironmentObject private var store: DataStore

  var body: some View {
    let snapshot = store.workspaceSnapshot()
    let dashboards = WorkspaceCollections.dashboards(snapshot: snapshot, segments: store.segments)
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        Text(tr("workspace.projectDashboard")).font(.title2.bold())
        Spacer()
        Button(tr("workspace.openProjects")) { onOpenSection(.projects) }
      }
      if dashboards.isEmpty {
        ContentUnavailableView(
          tr("workspace.noProjects"), systemImage: "folder.badge.plus",
          description: Text(tr("workspace.noProjectsDescription"))
        )
        .frame(maxWidth: .infinity, minHeight: 150)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)], spacing: 14
        ) {
          ForEach(dashboards) { dashboard in ProjectDashboardCard(summary: dashboard) }
        }
      }
      Divider()
      HStack {
        Text(tr("workspace.savedSearches")).font(.title2.bold())
        Spacer()
        Button(tr("workspace.manage")) { onOpenSection(.workspace) }
      }
      if store.savedSearches.isEmpty {
        Text(tr("workspace.noSavedSearches")).foregroundStyle(.secondary)
      } else {
        ForEach(store.savedSearches.prefix(5)) { saved in
          HStack {
            VStack(alignment: .leading) {
              Text(saved.name).fontWeight(.semibold)
              Text(saved.query).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(tr("workspace.run")) { onRunSavedSearch(saved) }
          }
          .padding(12)
          .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
  }
}

private struct ProjectDashboardCard: View {
  let summary: ProjectDashboardSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(summary.project.name, systemImage: "folder.fill")
        .font(.headline).lineLimit(1)
      Text(
        tr(
          "workspace.lastActivity",
          summary.lastActivity.formatted(date: .abbreviated, time: .shortened))
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 12) {
        WorkspaceMetric(icon: "heart", value: summary.favoriteCount, label: tr("nav.favorites"))
        WorkspaceMetric(
          icon: "arrow.down.circle", value: summary.downloadCount, label: tr("nav.downloads"))
        WorkspaceMetric(
          icon: "book", value: summary.researchNoteCount, label: tr("research.notes"))
      }
      if summary.rightsUnknownCount > 0 {
        Label(
          tr("workspace.rightsNeedsReview", summary.rightsUnknownCount),
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption).foregroundStyle(.orange)
        .accessibilityLabel(tr("workspace.rightsNeedsReview", summary.rightsUnknownCount))
      }
      if summary.attributionRequiredCount > 0 || summary.missingLocalMediaCount > 0
        || summary.possibleDuplicateCount > 0
      {
        HStack(spacing: 8) {
          if summary.attributionRequiredCount > 0 {
            Label(
              tr("workspace.attributionRequired", summary.attributionRequiredCount),
              systemImage: "text.badge.checkmark")
          }
          if summary.missingLocalMediaCount > 0 {
            Label(
              tr("workspace.missingLocalMedia", summary.missingLocalMediaCount),
              systemImage: "externaldrive.badge.xmark")
          }
          if summary.possibleDuplicateCount > 0 {
            Label(
              tr("workspace.possibleDuplicates", summary.possibleDuplicateCount),
              systemImage: "rectangle.on.rectangle")
          }
        }
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct WorkspaceMetric: View {
  let icon: String
  let value: Int
  let label: String
  var body: some View {
    Label("\(value)", systemImage: icon).font(.caption)
      .accessibilityLabel("\(label): \(value)")
  }
}

struct SavedSearchesPane: View {
  let onRun: (SavedSearchRecord) -> Void
  @EnvironmentObject private var store: DataStore
  @State private var renameID: UUID?
  @State private var renameText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("workspace.savedSearches")).font(.title2.bold())
      Text(tr("workspace.savedSearchesDetail")).font(.callout).foregroundStyle(.secondary)
      if store.savedSearches.isEmpty {
        ContentUnavailableView(
          tr("workspace.noSavedSearches"), systemImage: "bookmark",
          description: Text(tr("workspace.noSavedSearchesDescription"))
        )
        .frame(maxWidth: .infinity, minHeight: 260)
      }
      ForEach(store.savedSearches) { saved in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            if renameID == saved.id {
              TextField(tr("workspace.savedSearchName"), text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveRename(saved) }
            } else {
              Text(saved.name).font(.headline)
            }
            Spacer()
            Button(tr("workspace.run")) { onRun(saved) }.buttonStyle(.borderedProminent)
            Button(tr("workspace.rename")) {
              renameID = saved.id
              renameText = saved.name
            }
            Button(tr("workspace.duplicate")) { _ = store.duplicateSavedSearch(id: saved.id) }
            Button(role: .destructive) {
              store.deleteSavedSearch(id: saved.id)
            } label: {
              Image(systemName: "trash")
            }.help(tr("common.delete"))
          }
          Text(saved.query).foregroundStyle(.secondary).lineLimit(2)
          Text(savedSummary(saved)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  private func saveRename(_ saved: SavedSearchRecord) {
    var updated = saved
    updated.name = renameText
    store.updateSavedSearch(updated)
    renameID = nil
  }

  private func savedSummary(_ saved: SavedSearchRecord) -> String {
    let providers = saved.providerSet.count
    return tr("workspace.savedSearchSummary", saved.mediaType.label, providers)
  }
}

private struct SmartCollectionsPane: View {
  let onOpenSection: (AppSection) -> Void
  @EnvironmentObject private var store: DataStore

  var body: some View {
    let summaries = WorkspaceCollections.summaries(snapshot: store.workspaceSnapshot())
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("workspace.smartCollections")).font(.title2.bold())
      Text(tr("workspace.smartCollectionsDetail")).foregroundStyle(.secondary)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14
      ) {
        ForEach(summaries) { collection in
          Button {
            switch collection.id {
            case .downloadedMedia, .recentDownloads, .missingLocalMedia:
              onOpenSection(.downloads)
            case .recentFavorites, .unknownRights, .attributionRequired, .possibleDuplicates:
              onOpenSection(.favorites)
            case .researchWithoutNotes, .recentResearch: onOpenSection(.projects)
            }
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(tr(collection.id.titleKey)).font(.headline)
              Text("\(collection.count)").font(.system(size: 30, weight: .bold, design: .rounded))
              Text(tr("workspace.smartCollectionDynamic")).font(.caption).foregroundStyle(
                .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(14)
          }
          .buttonStyle(.plain)
          .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
          .accessibilityLabel("\(tr(collection.id.titleKey)): \(collection.count)")
        }
      }
    }
  }
}

private struct ProviderHealthPane: View {
  @EnvironmentObject private var store: DataStore
  @State private var checking = Set<ProviderID>()
  @State private var testAllTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(tr("workspace.providerHealth")).font(.title2.bold())
          Text(tr("workspace.providerHealthDetail")).foregroundStyle(.secondary)
        }
        Spacer()
        if testAllTask == nil {
          Button(tr("workspace.testAll")) { testAll() }.disabled(!checking.isEmpty)
        } else {
          Button(tr("common.stop")) { cancelAll() }
        }
      }
      ForEach(ProviderID.searchCases) { provider in
        let record = record(for: provider)
        HStack(spacing: 12) {
          Image(systemName: symbol(for: record.state)).foregroundStyle(color(for: record.state))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(provider.displayName).fontWeight(.semibold)
            Text(statusText(record)).font(.caption).foregroundStyle(.secondary)
              .accessibilityLabel("\(provider.displayName): \(statusText(record))")
          }
          Spacer()
          if checking.contains(provider) { ProgressView().controlSize(.small) }
          Button(tr("workspace.test")) { test(provider) }.disabled(checking.contains(provider))
        }
        .padding(10)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 9))
      }
      Text(tr("workspace.providerHealthPrivacy")).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func record(for provider: ProviderID) -> ProviderHealthRecord {
    store.providerHealth.first(where: { $0.providerID == provider.rawValue })
      ?? ProviderHealthService.initialRecord(
        for: provider, enabled: AppSettings.enabledProviders.contains(provider))
  }

  private func testAll() {
    guard testAllTask == nil else { return }
    let providers = ProviderID.searchCases.filter { AppSettings.enabledProviders.contains($0) }
    checking.formUnion(providers)
    testAllTask = Task {
      // A two-at-a-time probe is intentionally conservative: this is a
      // user-initiated diagnostic, not an uptime monitor or quota stress test.
      await withTaskGroup(of: (ProviderID, ProviderHealthRecord).self) { group in
        var iterator = providers.makeIterator()
        for _ in 0..<min(2, providers.count) {
          if let provider = iterator.next() {
            group.addTask { (provider, await ProviderHealthService.test(provider)) }
          }
        }
        while let result = await group.next() {
          guard !Task.isCancelled else {
            group.cancelAll()
            break
          }
          store.updateProviderHealth(result.1)
          checking.remove(result.0)
          if let provider = iterator.next() {
            group.addTask { (provider, await ProviderHealthService.test(provider)) }
          }
        }
      }
      testAllTask = nil
    }
  }

  private func cancelAll() {
    testAllTask?.cancel()
    testAllTask = nil
    checking.removeAll()
  }

  private func test(_ provider: ProviderID) {
    guard checking.insert(provider).inserted else { return }
    Task {
      let result = await ProviderHealthService.test(provider)
      await MainActor.run {
        store.updateProviderHealth(result)
        checking.remove(provider)
      }
    }
  }

  private func statusText(_ record: ProviderHealthRecord) -> String {
    var parts = [tr(record.state.localizationKey)]
    if let response = record.responseTimeMilliseconds { parts.append("\(response) ms") }
    if let testedAt = record.testedAt {
      parts.append(testedAt.formatted(date: .abbreviated, time: .shortened))
    }
    if let message = record.message, !message.isEmpty { parts.append(message) }
    return parts.joined(separator: " · ")
  }
  private func symbol(for state: ProviderHealthState) -> String {
    switch state {
    case .healthy: "checkmark.circle.fill"
    case .rateLimited: "clock.badge.exclamationmark"
    case .disabled: "minus.circle"
    case .ready, .unknown: "circle"
    case .checking: "arrow.triangle.2.circlepath"
    case .limited, .apiKeyRequired, .authenticationRequired, .degraded: "exclamationmark.circle"
    case .unavailable: "xmark.circle.fill"
    }
  }
  private func color(for state: ProviderHealthState) -> Color {
    switch state {
    case .healthy: .green
    case .rateLimited, .limited, .apiKeyRequired, .authenticationRequired, .degraded: .orange
    case .unavailable: .red
    case .disabled: .secondary
    case .ready, .checking, .unknown: .blue
    }
  }
}

private struct ShortcutReferencePane: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("workspace.shortcuts")).font(.title2.bold())
      Text(tr("workspace.shortcutsDetail")).foregroundStyle(.secondary)
      ForEach(WorkspaceCommand.catalog) { command in
        HStack {
          VStack(alignment: .leading) {
            Text(tr(command.id.titleKey)).fontWeight(.semibold)
            Text(tr(command.id.subtitleKey)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          if !command.shortcut.isEmpty {
            Text(command.shortcut).font(.system(.body, design: .monospaced)).foregroundStyle(
              .secondary)
          }
        }
        .padding(10)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 9))
      }
    }
  }
}

struct WorkspaceCommandPalette: View {
  let onSelect: (WorkspaceCommandID) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var selectedID: WorkspaceCommandID?
  @FocusState private var queryFocused: Bool

  private var matches: [WorkspaceCommand] {
    let needle = query.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    guard !needle.isEmpty else { return WorkspaceCommand.catalog }
    return WorkspaceCommand.catalog.filter {
      WorkspaceCommand.fuzzyMatches(
        [tr($0.id.titleKey), tr($0.id.subtitleKey), $0.id.rawValue].joined(separator: " "),
        query: needle)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField(tr("workspace.commandPalettePlaceholder"), text: $query)
        .textFieldStyle(.roundedBorder).font(.title3).padding(18)
        .accessibilityLabel(tr("workspace.commandPalette"))
        .focused($queryFocused)
        .onSubmit { runSelected() }
      Divider()
      List(matches, selection: $selectedID) { command in
        Button {
          dismiss()
          onSelect(command.id)
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(tr(command.id.titleKey))
              Text(tr(command.id.subtitleKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(command.shortcut).foregroundStyle(.secondary)
          }
        }.buttonStyle(.plain).tag(command.id)
          .accessibilityLabel(tr(command.id.titleKey))
          .accessibilityHint(tr(command.id.subtitleKey))
      }
    }
    .frame(width: 660, height: 470)
    .onAppear {
      selectedID = matches.first?.id
      queryFocused = true
    }
    .onChange(of: query) { _, _ in selectedID = matches.first?.id }
    .onMoveCommand { direction in
      moveSelection(direction == .down ? 1 : -1)
    }
    .onExitCommand { dismiss() }
  }

  private func moveSelection(_ delta: Int) {
    guard !matches.isEmpty else { return }
    let current = selectedID.flatMap { id in matches.firstIndex { $0.id == id } } ?? 0
    selectedID = matches[(current + delta + matches.count) % matches.count].id
  }

  private func runSelected() {
    guard let id = selectedID ?? matches.first?.id else { return }
    dismiss()
    onSelect(id)
  }
}

struct WorkspaceGlobalSearch: View {
  let onSelect: (WorkspaceSearchEntry) -> Void
  @EnvironmentObject private var store: DataStore
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [WorkspaceSearchEntry] = []
  @State private var selectedID: String?
  @FocusState private var queryFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField(tr("workspace.globalSearchPlaceholder"), text: $query)
        .textFieldStyle(.roundedBorder).font(.title3).padding(18)
        .accessibilityLabel(tr("workspace.globalSearch"))
        .focused($queryFocused)
        .onSubmit { openSelected() }
      Divider()
      List(selection: $selectedID) {
        ForEach(WorkspaceItemKind.allCases, id: \.self) { kind in
          let section = results.filter { $0.kind == kind }
          if !section.isEmpty {
            Section(tr(kind.localizationKey)) {
              ForEach(section) { entry in
                Button {
                  dismiss()
                  onSelect(entry)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                    if !entry.detail.isEmpty {
                      Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                  }
                }.buttonStyle(.plain).tag(entry.id)
                  .accessibilityLabel("\(tr(kind.localizationKey)): \(entry.title)")
              }
            }
          }
        }
      }
    }
    .frame(width: 760, height: 560)
    .task {
      queryFocused = true
      await rebuildAndSearch()
    }
    .task(id: query) {
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled else { return }
      await rebuildAndSearch()
    }
    .onChange(of: store.projects) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: store.favorites) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: store.downloads) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: store.history) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: store.researchReferences) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: store.savedSearches) { _, _ in Task { await rebuildAndSearch() } }
    .onChange(of: results) { _, values in selectedID = values.first?.id }
    .onMoveCommand { direction in
      guard !results.isEmpty else { return }
      let current = selectedID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
      selectedID =
        results[(current + (direction == .down ? 1 : -1) + results.count) % results.count].id
    }
    .onExitCommand { dismiss() }
  }

  private func rebuildAndSearch() async {
    await WorkspaceSearchIndex.shared.rebuild(snapshot: store.workspaceSnapshot())
    let values = await WorkspaceSearchIndex.shared.search(query)
    await MainActor.run { results = values }
  }

  private func openSelected() {
    guard let id = selectedID ?? results.first?.id,
      let entry = results.first(where: { $0.id == id })
    else { return }
    dismiss()
    onSelect(entry)
  }
}

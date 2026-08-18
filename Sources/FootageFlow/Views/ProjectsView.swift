import SwiftUI

#if os(macOS)
  import AppKit
  import UniformTypeIdentifiers
#endif

struct ProjectsView: View {
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var selectedID: UUID?
  @State private var newName = ""
  @State private var showNewProject = false
  @State private var confirmDelete = false
  @State private var importError: String?

  private var selected: ProjectRecord? {
    selectedID.flatMap { id in store.projects.first { $0.id == id } }
  }
  private var recentProjects: [ProjectRecord] {
    store.projects.sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    let _ = localization.language
    HSplitView {
      VStack(spacing: 0) {
        HStack {
          Text(tr("project.title")).font(.title2.bold())
          Spacer()
          Button {
            showNewProject = true
          } label: {
            Image(systemName: "plus")
          }.help(tr("project.new"))
          Button {
            importProject()
          } label: {
            Label(tr("project.import"), systemImage: "square.and.arrow.down")
          }
        }.padding()
        List(recentProjects, selection: $selectedID) { project in
          VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
            Text(
              tr(
                "project.updated",
                project.updatedAt.formatted(
                  .dateTime.locale(localization.locale)
                    .year().month(.abbreviated).day().hour().minute()
                )
              )
            ).font(.caption).foregroundStyle(.secondary)
          }.tag(project.id)
        }
      }.frame(minWidth: 250, idealWidth: 300)
      if let project = selected {
        ProjectDetail(project: project, onDelete: { confirmDelete = true })
      } else {
        ContentUnavailableView(
          tr("project.selectOrCreate"), systemImage: "folder",
          description: Text(tr("project.selectDescription")))
      }
    }
    .sheet(isPresented: $showNewProject) {
      VStack(alignment: .leading, spacing: 16) {
        Text(tr("project.new")).font(.title2.bold())
        TextField(tr("project.name"), text: $newName).textFieldStyle(.roundedBorder).onSubmit {
          createProject()
        }
        HStack {
          Spacer()
          Button(tr("common.cancel")) { showNewProject = false }
          Button(tr("common.create")) { createProject() }.buttonStyle(.borderedProminent)
            .disabled(
              newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.padding(24).frame(width: 420)
    }
    .alert(tr("project.deleteTitle"), isPresented: $confirmDelete) {
      Button(tr("common.cancel"), role: .cancel) {}
      Button(tr("project.delete"), role: .destructive) {
        if let selectedID {
          store.deleteProject(id: selectedID)
          self.selectedID = nil
        }
      }
    } message: {
      Text(tr("project.deleteHelp"))
    }
    .alert(
      tr("project.import"),
      isPresented: Binding(
        get: { importError != nil }, set: { if !$0 { importError = nil } })
    ) {
      Button(tr("common.close"), role: .cancel) {}
    } message: {
      Text(importError ?? "")
    }
  }

  private func createProject() {
    let project = store.addProject(name: newName)
    selectedID = project.id
    newName = ""
    showNewProject = false
  }

  private func importProject() {
    #if os(macOS)
      let panel = NSOpenPanel()
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.allowsMultipleSelection = false
      panel.allowedContentTypes = [UTType(filenameExtension: "footageflowproject") ?? .json]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        let project = try store.importPortableProject(data: Data(contentsOf: url))
        selectedID = project.id
      } catch {
        importError = error.localizedDescription
      }
    #endif
  }
}

private struct ProjectDetail: View {
  let project: ProjectRecord
  let onDelete: () -> Void
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var audit: RightsAuditReport?
  @State private var duplicates: [DuplicateGroup] = []
  @State private var actionMessage: String?
  @State private var isWorking = false
  @State private var pendingReportFormat: AttributionExportFormat?
  @State private var pendingReportIncludesLocalPaths = false
  @State private var showRightsExportWarning = false
  @State private var rightsAuditFilter: RightsAuditFilter = .all

  var body: some View {
    let _ = localization.language
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        TextField(
          tr("project.name"),
          text: Binding(
            get: { project.name },
            set: { value in
              var updated = project
              updated.name = value
              store.updateProject(updated)
            })
        )
        .textFieldStyle(.plain).font(.largeTitle.bold())
        Button {
          openProjectFolder()
        } label: {
          Label(tr("project.openFolder"), systemImage: "folder")
        }
        Button(role: .destructive, action: onDelete) {
          Label(tr("project.delete"), systemImage: "trash")
        }
      }
      projectActions
      if let actionMessage {
        Text(actionMessage).font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 20) {
        Label(
          tr(
            "project.favoriteCount", store.favorites.filter { $0.projectID == project.id }.count),
          systemImage: "heart")
        Label(
          tr(
            "project.downloadCount", store.downloads.filter { $0.projectID == project.id }.count),
          systemImage: "arrow.down.circle")
        Label(
          tr("project.searchCount", store.history.filter { $0.projectID == project.id }.count),
          systemImage: "magnifyingglass")
      }.foregroundStyle(.secondary)
      Text(tr("project.script")).font(.headline)
      TextEditor(
        text: Binding(
          get: { project.script },
          set: { value in
            var updated = project
            updated.script = value
            store.updateProject(updated)
          })
      )
      .font(.body).padding(8).background(
        .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      rightsAuditView
      duplicateView
    }.padding(22)
      .task(id: project.id) { refreshAudit() }
      .confirmationDialog(
        tr("project.rightsExportWarning"), isPresented: $showRightsExportWarning,
        titleVisibility: .visible
      ) {
        Button(tr("project.reviewRights")) { refreshAudit() }
        Button(tr("project.exportAnyway")) {
          guard let format = pendingReportFormat else { return }
          saveReport(format, includeLocalFilePaths: pendingReportIncludesLocalPaths)
        }
        Button(tr("common.cancel"), role: .cancel) {}
      } message: {
        Text(tr("project.rightsExportWarningDetail"))
      }
  }

  private var projectActions: some View {
    Menu {
      Menu(tr("project.attributionReport")) {
        reportMenu("Markdown (.md)", .markdown)
        reportMenu("CSV (.csv)", .csv)
        reportMenu("JSON (.json)", .json)
        reportMenu("HTML (.html)", .html)
      }
      Menu(tr("project.generateCredits")) {
        Button(tr("project.generateCredits")) { copyCredits(.concise) }
        Button(tr("project.creditsDetailed")) { copyCredits(.detailed) }
        Button(tr("project.saveText")) { saveCredits(.concise, extension: "txt") }
        Button(tr("project.saveMarkdown")) { saveCredits(.detailed, extension: "md") }
      }
      Button(tr("project.rightsAudit")) { refreshAudit() }
      Button(tr("project.backup")) { exportBackup() }
      Button(tr("project.findDuplicates")) { findDuplicates() }
      Menu(tr("project.contactSheet")) {
        Button(tr("project.contactSheetColumns", 3)) {
          generateContactSheet(columns: 3, includeRights: true)
        }
        Button(tr("project.contactSheetColumns", 4)) {
          generateContactSheet(columns: 4, includeRights: true)
        }
        Button(tr("project.contactSheetColumns", 5)) {
          generateContactSheet(columns: 5, includeRights: true)
        }
        Button(tr("project.contactSheetNoRights", 4)) {
          generateContactSheet(columns: 4, includeRights: false)
        }
      }
      if !duplicates.isEmpty {
        Button(tr("project.resetDuplicateDecisions")) {
          store.resetDuplicateDecisions(projectID: project.id)
          findDuplicates()
        }
      }
    } label: {
      Label(tr("project.actions"), systemImage: "ellipsis.circle")
    }.disabled(isWorking)
  }

  @ViewBuilder private var rightsAuditView: some View {
    if let audit {
      VStack(alignment: .leading, spacing: 8) {
        Text(tr("project.rightsAudit")).font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
          GridRow {
            auditSummary(tr("project.totalAssets"), audit.summary.totalAssets)
            auditSummary(tr("license.publicDomain"), audit.summary.publicDomain)
            auditSummary(tr("project.rightsKnown"), audit.summary.rightsKnown)
          }
          GridRow {
            auditSummary(tr("license.attribution"), audit.summary.attributionRequired)
            auditSummary(tr("project.rightsUnknown"), audit.summary.rightsUnknown)
            auditSummary(
              tr("project.originalPageUnavailable"), audit.summary.originalPageUnavailable)
          }
        }
        Text(tr("project.rightsAuditDisclaimer"))
          .font(.caption).foregroundStyle(.secondary)
        Picker(tr("project.auditFilter"), selection: $rightsAuditFilter) {
          ForEach(RightsAuditFilter.allCases, id: \.self) { filter in
            Text(tr(filter.localizationKey)).tag(filter)
          }
        }.pickerStyle(.segmented).accessibilityLabel(tr("project.auditFilter"))
        ForEach(audit.entries.filter { rightsAuditFilter.includes($0) }) { entry in
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.item.title).font(.subheadline.weight(.medium))
              Text("\(entry.item.providerName) · \(AttributionExporter.rightsStatus(entry.item))")
                .font(.caption).foregroundStyle(.secondary)
              if entry.item.localMediaMissing {
                Text(tr("project.missingLocalMedia")).font(.caption).foregroundStyle(.orange)
              }
              if entry.needsReview {
                Text(tr("project.needsReview")).font(.caption).foregroundStyle(.orange)
              }
            }
            Spacer()
            if entry.needsReview {
              Button(tr("project.markReviewed")) {
                store.setReviewed(
                  projectID: project.id, stableAssetID: entry.item.stableID, reviewed: true)
                refreshAudit()
              }.controlSize(.small)
            }
            if let url = entry.item.sourcePageURL {
              Button(tr("project.openOriginal")) { DesktopPlatform.shared.open(url) }.controlSize(
                .small)
            }
          }.padding(8).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
        }
      }
    }
  }

  @ViewBuilder private var duplicateView: some View {
    if !duplicates.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(tr("project.findDuplicates")).font(.headline)
        ForEach(duplicates) { group in
          VStack(alignment: .leading, spacing: 5) {
            Text(group.displayReason ?? DuplicateDetectionEngine.displayReason(group.reason))
              .font(.subheadline.weight(.medium))
            ForEach(group.items) { item in
              HStack {
                Text(item.title).font(.caption)
                Spacer()
                if let source = item.sourcePageURL {
                  Button(tr("project.openOriginal")) { DesktopPlatform.shared.open(source) }
                    .controlSize(.mini)
                }
                if let path = item.localPath, !path.isEmpty,
                  FileManager.default.fileExists(atPath: path)
                {
                  Button(tr("project.revealFile")) {
                    DesktopPlatform.shared.reveal(URL(fileURLWithPath: path))
                  }.controlSize(.mini)
                }
                Button(tr("project.removeFromProject")) {
                  store.removeAssetFromProject(projectID: project.id, stableAssetID: item.stableID)
                  refreshAudit()
                  findDuplicates()
                }.controlSize(.mini)
              }
            }
            HStack {
              Button(tr("project.keepBoth")) { decide(group, .keepBoth) }
              Button(tr("project.notDuplicate")) { decide(group, .notDuplicate) }
            }.controlSize(.small)
          }.padding(8).background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
      }
    }
  }

  @ViewBuilder private func auditSummary(_ label: String, _ value: Int) -> some View {
    Text("\(label): \(value)").font(.subheadline).foregroundStyle(.secondary)
  }

  private func refreshAudit() {
    audit = store.rightsAudit(projectID: project.id)
  }

  private func findDuplicates() {
    isWorking = true
    actionMessage = tr("project.scanningDuplicates")
    Task {
      duplicates = await store.findDuplicates(projectID: project.id)
      actionMessage = duplicates.isEmpty ? tr("project.noDuplicates") : nil
      isWorking = false
    }
  }

  private func decide(_ group: DuplicateGroup, _ decision: DuplicateDecision) {
    store.setDuplicateDecision(
      projectID: project.id, pairKey: group.decisionKey, decision: decision)
    duplicates.removeAll { $0.id == group.id }
  }

  @ViewBuilder private func reportMenu(_ title: String, _ format: AttributionExportFormat)
    -> some View
  {
    Menu(title) {
      Button(tr("project.withoutLocalPaths")) { exportReport(format, includeLocalFilePaths: false) }
      Button(tr("project.includeLocalPaths")) { exportReport(format, includeLocalFilePaths: true) }
    }
  }

  private func exportReport(_ format: AttributionExportFormat, includeLocalFilePaths: Bool) {
    let currentAudit = audit ?? store.rightsAudit(projectID: project.id)
    if currentAudit.summary.rightsUnknown > 0 || currentAudit.summary.originalPageUnavailable > 0 {
      pendingReportFormat = format
      pendingReportIncludesLocalPaths = includeLocalFilePaths
      showRightsExportWarning = true
      return
    }
    saveReport(format, includeLocalFilePaths: includeLocalFilePaths)
  }

  private func saveReport(_ format: AttributionExportFormat, includeLocalFilePaths: Bool) {
    #if os(macOS)
      let panel = savePanel(
        name: "\(FileNameSanitizer.sanitize(project.name))-attribution",
        extension: format.fileExtension)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        try store.attributionData(
          project: project, format: format,
          options: AttributionExportOptions(includeLocalFilePaths: includeLocalFilePaths)
        ).write(to: url, options: .atomic)
      } catch { actionMessage = tr("project.actionFailed") }
    #endif
  }

  private func copyCredits(_ style: CreditsStyle) {
    DesktopPlatform.shared.copy(store.credits(projectID: project.id, style: style))
  }

  private func saveCredits(_ style: CreditsStyle, extension fileExtension: String) {
    #if os(macOS)
      let panel = savePanel(
        name: "\(FileNameSanitizer.sanitize(project.name))-credits", extension: fileExtension)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        try Data(store.credits(projectID: project.id, style: style).utf8).write(
          to: url, options: .atomic)
      } catch { actionMessage = tr("project.actionFailed") }
    #endif
  }

  private func exportBackup() {
    #if os(macOS)
      let panel = savePanel(
        name: FileNameSanitizer.sanitize(project.name), extension: "footageflowproject")
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do { try store.portableProjectData(project: project).write(to: url, options: .atomic) } catch
      { actionMessage = tr("project.actionFailed") }
    #endif
  }

  private func generateContactSheet(columns: Int, includeRights: Bool) {
    #if os(macOS)
      let panel = savePanel(
        name: "\(FileNameSanitizer.sanitize(project.name))-contact-sheet", extension: "png")
      guard panel.runModal() == .OK, let url = panel.url else { return }
      let plan = store.contactSheetPlan(
        project: project, columns: columns, includeRights: includeRights)
      isWorking = true
      actionMessage = tr("common.loading")
      Task {
        do {
          try await ProjectContactSheetRenderer.pngData(for: plan).write(to: url, options: .atomic)
          actionMessage = nil
        } catch { actionMessage = tr("project.actionFailed") }
        isWorking = false
      }
    #endif
  }

  #if os(macOS)
    private func savePanel(name: String, extension fileExtension: String) -> NSSavePanel {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "\(name).\(fileExtension)"
      panel.canCreateDirectories = true
      panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
      return panel
    }
  #endif

  private func openProjectFolder() {
    let existingDirectory = store.downloads.first { $0.projectID == project.id }.map {
      URL(fileURLWithPath: $0.localPath).deletingLastPathComponent()
    }
    let directory =
      existingDirectory ?? DownloadPathSafety.projectDirectory(projectName: project.name)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    DesktopPlatform.shared.open(directory)
  }
}

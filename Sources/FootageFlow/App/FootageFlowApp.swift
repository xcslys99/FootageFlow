import Darwin
import Dispatch
import SwiftUI

@main
struct FootageFlowApp: App {
  @StateObject private var store = DataStore.shared
  @StateObject private var search = SearchViewModel()
  @StateObject private var downloads = DownloadManager.shared
  @StateObject private var localization = LocalizationManager.shared
  @StateObject private var updates = AppUpdateController()
  @StateObject private var workspace = WorkspaceCoordinator()

  init() {
    AppSettings.migrateLegacySettingsIfNeeded()
    if CommandLine.arguments.contains("--self-test") { Darwin.exit(SelfTestRunner.run()) }
    if CommandLine.arguments.contains("--live-smoke") {
      Task.detached { Darwin.exit(await LiveSmokeRunner.run()) }
      dispatchMain()
    }
    if let index = CommandLine.arguments.firstIndex(of: "--creator-workflow-smoke") {
      let path =
        CommandLine.arguments.indices.contains(index + 1)
        ? CommandLine.arguments[index + 1]
        : FileManager.default.temporaryDirectory.appendingPathComponent(
          "FootageFlowCreatorWorkflowSmoke", isDirectory: true
        ).path
      Task.detached {
        Darwin.exit(
          await CreatorWorkflowSmokeRunner.run(
            directory: URL(fileURLWithPath: path, isDirectory: true)))
      }
      dispatchMain()
    }
    if CommandLine.arguments.contains("--update-smoke") {
      Task.detached { Darwin.exit(await UpdateSmokeRunner.run()) }
      dispatchMain()
    }
    if CommandLine.arguments.contains("--thumbnail-smoke") {
      let query =
        CommandLine.arguments.last == "--thumbnail-smoke" ? "city" : CommandLine.arguments.last!
      Task.detached { Darwin.exit(await ThumbnailDiagnosticsRunner.run(query: query)) }
      dispatchMain()
    }
    if CommandLine.arguments.contains("--relevance-smoke") {
      let query =
        CommandLine.arguments.last == "--relevance-smoke" ? "台湾美食" : CommandLine.arguments.last!
      Task.detached {
        let status = await RelevanceSmokeRunner.run(query: query)
        fflush(stdout)
        Darwin.exit(status)
      }
      dispatchMain()
    }
    if CommandLine.arguments.contains("--research-smoke") {
      let query =
        CommandLine.arguments.last == "--research-smoke" ? "Apollo 11" : CommandLine.arguments.last!
      Task.detached {
        let status = await ResearchSmokeRunner.run(query: query)
        fflush(stdout)
        Darwin.exit(status)
      }
      dispatchMain()
    }
    if let index = CommandLine.arguments.firstIndex(of: "--acceptance-test") {
      let path =
        CommandLine.arguments.indices.contains(index + 1)
        ? CommandLine.arguments[index + 1]
        : FileManager.default.temporaryDirectory.appendingPathComponent("FootageFlowAcceptance")
          .path
      Task.detached {
        Darwin.exit(
          await AcceptanceRunner.run(directory: URL(fileURLWithPath: path, isDirectory: true)))
      }
      dispatchMain()
    }
  }

  var body: some Scene {
    WindowGroup("FootageFlow") {
      RootView()
        .environmentObject(store)
        .environmentObject(search)
        .environmentObject(downloads)
        .environmentObject(localization)
        .environmentObject(updates)
        .environmentObject(workspace)
        .environment(\.locale, localization.locale)
        .frame(minWidth: 1080, minHeight: 700)
        .onAppear {
          search.configure(store: store)
          downloads.configure(store: store)
        }
    }
    .windowStyle(.automatic)
    .defaultSize(width: 1320, height: 850)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandMenu(tr("workspace.commandMenu")) {
        Button(tr("workspace.command.focusSearch")) { workspace.perform(.focusSearch) }
          .keyboardShortcut("f", modifiers: .command)
        Button(tr("workspace.command.globalSearch")) { workspace.perform(.globalSearch) }
          .keyboardShortcut("g", modifiers: [.command, .shift])
        Button(tr("workspace.command.palette")) { workspace.perform(.commandPalette) }
          .keyboardShortcut("k", modifiers: .command)
        Divider()
        Button(tr("workspace.command.newProject")) { workspace.perform(.newProject) }
          .keyboardShortcut("n", modifiers: .command)
        Button(tr("workspace.command.openProjects")) { workspace.perform(.openProjects) }
          .keyboardShortcut("o", modifiers: .command)
        Button(tr("workspace.command.openFavorites")) { workspace.perform(.openFavorites) }
          .keyboardShortcut("f", modifiers: [.command, .shift])
        Button(tr("workspace.command.openDownloads")) { workspace.perform(.openDownloads) }
          .keyboardShortcut("d", modifiers: [.command, .shift])
        Button(tr("workspace.command.openResearchNotes")) { workspace.perform(.openResearchNotes) }
          .keyboardShortcut("r", modifiers: [.command, .shift])
        Button(tr("workspace.command.openSettings")) { workspace.perform(.openSettings) }
          .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
}

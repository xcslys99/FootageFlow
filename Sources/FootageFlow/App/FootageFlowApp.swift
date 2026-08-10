import SwiftUI
import Darwin
import Dispatch

@main
struct FootageFlowApp: App {
    @StateObject private var store = DataStore.shared
    @StateObject private var search = SearchViewModel()
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var localization = LocalizationManager.shared
    @AppStorage("didFinishWelcome") private var didFinishWelcome = false

    init() {
        AppSettings.migrateLegacySettingsIfNeeded()
        if CommandLine.arguments.contains("--self-test") { Darwin.exit(SelfTestRunner.run()) }
        if CommandLine.arguments.contains("--live-smoke") {
            Task.detached { Darwin.exit(await LiveSmokeRunner.run()) }
            dispatchMain()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--acceptance-test") {
            let path = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : FileManager.default.temporaryDirectory.appendingPathComponent("FootageFlowAcceptance").path
            Task.detached { Darwin.exit(await AcceptanceRunner.run(directory: URL(fileURLWithPath: path, isDirectory: true))) }
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
                .environment(\.locale, localization.locale)
                .frame(minWidth: 1080, minHeight: 700)
                .onAppear {
                    search.configure(store: store)
                    downloads.configure(store: store)
                }
                .sheet(isPresented: Binding(get: { !didFinishWelcome }, set: { if !$0 { didFinishWelcome = true } })) {
                    WelcomeView { didFinishWelcome = true }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1320, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

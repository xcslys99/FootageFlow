import Foundation

@MainActor
protocol DesktopPlatformServing {
  func open(_ url: URL)
  func reveal(_ url: URL)
  func chooseDirectory(prompt: String) -> URL?
}

enum DesktopPlatform {
  @MainActor static let shared: any DesktopPlatformServing = SystemDesktopPlatform()
}

#if os(macOS)
  import AppKit

  private struct SystemDesktopPlatform: DesktopPlatformServing {
    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func chooseDirectory(prompt: String) -> URL? {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.prompt = prompt
      return panel.runModal() == .OK ? panel.url : nil
    }
  }
#else
  private struct SystemDesktopPlatform: DesktopPlatformServing {
    func open(_ url: URL) {}
    func reveal(_ url: URL) {}
    func chooseDirectory(prompt: String) -> URL? { nil }
  }
#endif

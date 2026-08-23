import Foundation

@MainActor
final class WorkspaceCoordinator: ObservableObject {
  @Published var requestedCommand: WorkspaceCommandID?
  @Published var isCommandPalettePresented = false
  @Published var isGlobalSearchPresented = false
  @Published private(set) var searchFocusRequest = UUID()

  func perform(_ command: WorkspaceCommandID) {
    switch command {
    case .commandPalette:
      isCommandPalettePresented = true
    case .globalSearch:
      isGlobalSearchPresented = true
    case .focusSearch:
      searchFocusRequest = UUID()
      requestedCommand = command
    default:
      requestedCommand = command
    }
  }

  func complete(_ command: WorkspaceCommandID) {
    if requestedCommand == command { requestedCommand = nil }
  }
}

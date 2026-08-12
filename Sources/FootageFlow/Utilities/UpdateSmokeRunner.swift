import Foundation

enum UpdateSmokeRunner {
  static func run() async -> Int32 {
    do {
      switch try await AppUpdateService.shared.check() {
      case .upToDate(let latestVersion):
        print(
          "UPDATE_SMOKE current=\(FootageFlowVersion.current) latest=\(latestVersion) status=upToDate"
        )
      case .updateAvailable(let release):
        print(
          "UPDATE_SMOKE current=\(FootageFlowVersion.current) latest=\(release.version) status=available notes=\(release.notes.count)"
        )
      }
      return 0
    } catch let error as AppUpdateCheckError {
      print("UPDATE_SMOKE failed=\(error.code)")
      return 1
    } catch {
      print("UPDATE_SMOKE failed=invalidResponse")
      return 1
    }
  }
}

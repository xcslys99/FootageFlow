import Foundation

enum ResearchSmokeRunner {
  static func run(query: String = "Apollo 11") async -> Int32 {
    var successes = 0
    for id in ResearchProviderID.allCases {
      do {
        let page = try await ResearchProviderFactory.make(id).search(
          ResearchSearchRequest(query: query, interfaceLanguage: .english, pageSize: 3),
          continuation: nil)
        let count = page.records.count
        emit("RESEARCH_SMOKE \(id.rawValue) count=\(count)")
        if count > 0 { successes += 1 }
      } catch {
        // Public interfaces can be unavailable independently. The runner is
        // diagnostic; one provider never prevents the rest from being tested.
        emit("RESEARCH_SMOKE \(id.rawValue) error=\(String(describing: error))")
      }
    }
    emit("RESEARCH_SMOKE successes=\(successes)/\(ResearchProviderID.allCases.count)")
    return successes >= 4 ? 0 : 1
  }

  private static func emit(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
  }
}

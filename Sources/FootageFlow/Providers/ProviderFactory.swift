import Foundation

enum ProviderFactory {
  static func make(
    _ id: ProviderID, apiKey: String,
    directLoader: any DirectSearchPageLoading = LiveDirectSearchPageLoader(),
    ytDLPService: YTDLPService = YTDLPService()
  ) -> any MediaProvider {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    switch id {
    case .pexels:
      return key.isEmpty ? PexelsDirectProvider(loader: directLoader) : PexelsProvider(apiKey: key)
    case .pixabay:
      return key.isEmpty
        ? PixabayDirectProvider(loader: directLoader) : PixabayProvider(apiKey: key)
    case .wikimedia: return WikimediaProvider()
    case .internetArchive: return InternetArchiveProvider()
    case .youtube:
      return key.isEmpty
        ? YouTubeYTDLPProvider(service: ytDLPService) : YouTubeProvider(apiKey: key)
    }
  }

  static func current(_ id: ProviderID) -> any MediaProvider {
    make(id, apiKey: KeychainService.read(id))
  }

  static func currentProviders() -> [any MediaProvider] {
    ProviderID.allCases.map(current)
  }
}

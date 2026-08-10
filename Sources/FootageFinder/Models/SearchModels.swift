import Foundation

struct SearchKeyword: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var isEnabled = true
}

struct SearchRequest: Sendable {
    var query: String
    var mediaType: MediaType = .video
    var orientation: AssetOrientation = .all
    var resolution: ResolutionFilter = .all
    var duration: DurationFilter = .all
    var pageSize: Int = 16
}

struct ProviderInfo: Sendable {
    let id: ProviderID
    let displayName: String
    let requiresAPIKey: Bool
    let supportsVideo: Bool
    let supportsImage: Bool
    let supportsDownload: Bool
}

struct ProviderSearchResult: Sendable {
    let provider: ProviderID
    let assets: [MediaAsset]
    let errorMessage: String?
}

enum ProviderError: LocalizedError, Sendable {
    case missingAPIKey(ProviderID)
    case invalidAPIKey
    case noNetwork
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case serverUnavailable
    case invalidResponse
    case unsupported
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): "\(provider.displayName)：尚未配置 API Key"
        case .invalidAPIKey: "API Key 无效"
        case .noNetwork: "无法连接网络"
        case .rateLimited: "请求次数过多，请稍后再试"
        case .notFound: "该素材已失效"
        case .serverUnavailable: "服务器暂时不可用"
        case .invalidResponse: "素材平台返回了无法识别的数据"
        case .unsupported: "当前来源不支持这项操作"
        case .cancelled: "操作已取消"
        case .message(let text): text
        }
    }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case relevance, newest, resolution, duration
    var id: String { rawValue }
    var label: String { switch self { case .relevance: "相关度"; case .newest: "最新"; case .resolution: "分辨率"; case .duration: "时长" } }
}

enum LicenseFilter: String, CaseIterable, Identifiable {
    case all, safe, attribution, publicDomain, unknown
    var id: String { rawValue }
    var label: String {
        switch self { case .all: "全部"; case .safe: "明确可用"; case .attribution: "需要署名"; case .publicDomain: "Public Domain"; case .unknown: "授权未知" }
    }
    func matches(_ status: LicenseStatus) -> Bool {
        switch self { case .all: true; case .safe: status == .safe; case .attribution: status == .attributionRequired; case .publicDomain: status == .publicDomain; case .unknown: status == .unknown }
    }
}

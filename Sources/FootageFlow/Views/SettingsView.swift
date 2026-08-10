import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var pexelsKey = ""
    @State private var pixabayKey = ""
    @State private var youtubeKey = ""
    @State private var enabled = AppSettings.enabledProviders
    @State private var statuses: [ProviderID: String] = [:]
    @State private var messages: [ProviderID: String] = [:]
    @State private var cacheMessage = ""
    @State private var downloadRoot = AppSettings.downloadRootURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置").font(.largeTitle.bold())
                GroupBox("需要 API Key 的素材源") {
                    VStack(spacing: 0) {
                        keyRow(.pexels, key: $pexelsKey, applyURL: "https://www.pexels.com/api/")
                        Divider(); keyRow(.pixabay, key: $pixabayKey, applyURL: "https://pixabay.com/api/docs/")
                        Divider(); keyRow(.youtube, key: $youtubeKey, applyURL: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")
                    }.padding(6)
                }
                GroupBox("无需 API Key") {
                    VStack(spacing: 0) {
                        noKeyRow(.wikimedia, detail: "Wikimedia Commons 官方 MediaWiki API")
                        Divider(); noKeyRow(.internetArchive, detail: "Internet Archive Advanced Search / Metadata API")
                    }.padding(6)
                }
                GroupBox("下载与缓存") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("下载根目录") { HStack { Text(downloadRoot.path).lineLimit(1).foregroundStyle(.secondary); Button("选择…") { chooseFolder() } } }
                        HStack { Button("清理搜索缓存") { Task { do { try await SearchCache.shared.clear(); await MainActor.run { cacheMessage = "缓存已清理" } } catch { await MainActor.run { cacheMessage = "清理失败" } } } }; Text(cacheMessage).foregroundStyle(.secondary) }
                        Button("打开内部日志") { _ = NSWorkspace.shared.open(AppLogger.shared.logURL) }
                        Text("日志只记录来源、请求类型、HTTP 状态和错误类型，不记录 API Key。Pixabay 搜索结果按官方要求缓存 24 小时。").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("隐私") { Text("FootageFlow 不含分析、跟踪或广告 SDK。除向所选素材平台发出必要请求外，不上传你的项目、文稿、收藏或下载记录。API Key 只保存在 macOS Keychain。") .font(.callout).padding(8) }
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear { pexelsKey = KeychainService.read(.pexels); pixabayKey = KeychainService.read(.pixabay); youtubeKey = KeychainService.read(.youtube) }
    }

    private func keyRow(_ provider: ProviderID, key: Binding<String>, applyURL: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: enabledBinding(provider)).labelsHidden()
                Text(provider.displayName).font(.headline).frame(width: 110, alignment: .leading)
                SecureField("API Key", text: key).textFieldStyle(.roundedBorder)
                Button("保存") { saveKey(provider, value: key.wrappedValue) }
                Button("测试连接") { test(provider, key: key.wrappedValue) }.disabled(key.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("如何申请", destination: URL(string: applyURL)!)
            }
            HStack { Text(statuses[provider] ?? (key.wrappedValue.isEmpty ? "未配置" : "已配置")).foregroundStyle(statusColor(statuses[provider])); if let message = messages[provider] { Text(message).foregroundStyle(.secondary) } }.font(.caption)
        }.padding(.vertical, 10)
    }

    private func noKeyRow(_ provider: ProviderID, detail: String) -> some View {
        HStack { Toggle("", isOn: enabledBinding(provider)).labelsHidden(); VStack(alignment: .leading) { Text(provider.displayName).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(statuses[provider] ?? "已启用").foregroundStyle(statuses[provider] == "连接失败" ? .red : .green); Button("测试连接") { test(provider, key: "") } }.padding(.vertical, 10)
    }

    private func enabledBinding(_ provider: ProviderID) -> Binding<Bool> {
        Binding(get: { enabled.contains(provider) }, set: { value in if value { enabled.insert(provider) } else { enabled.remove(provider) }; AppSettings.enabledProviders = enabled })
    }
    private func saveKey(_ provider: ProviderID, value: String) {
        do { try KeychainService.save(value.trimmingCharacters(in: .whitespacesAndNewlines), provider: provider); statuses[provider] = value.isEmpty ? "未配置" : "已配置"; messages[provider] = "已安全保存到 Keychain" }
        catch { statuses[provider] = "保存失败"; messages[provider] = error.localizedDescription }
    }
    private func test(_ provider: ProviderID, key: String) {
        statuses[provider] = "正在连接…"; messages[provider] = nil
        Task {
            let source: any MediaProvider = switch provider {
            case .pexels: PexelsProvider(apiKey: key)
            case .pixabay: PixabayProvider(apiKey: key)
            case .youtube: YouTubeProvider(apiKey: key)
            case .wikimedia: WikimediaProvider()
            case .internetArchive: InternetArchiveProvider()
            }
            do { try await source.testConnection(); await MainActor.run { statuses[provider] = "连接成功" } }
            catch { await MainActor.run { statuses[provider] = "连接失败"; messages[provider] = error.localizedDescription } }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "选择下载目录"
        if panel.runModal() == .OK, let url = panel.url { downloadRoot = url; AppSettings.downloadRootURL = url }
    }
    private func statusColor(_ status: String?) -> Color { status == "连接成功" ? .green : ((status?.contains("失败") == true) ? .red : .secondary) }
}

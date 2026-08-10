import SwiftUI

struct WelcomeView: View {
    let finish: () -> Void
    @State private var pexels = ""
    @State private var pixabay = ""
    @State private var youtube = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) { Image(systemName: "film.stack").font(.system(size: 42)).foregroundStyle(.tint); VStack(alignment: .leading) { Text("欢迎使用素材猎手").font(.largeTitle.bold()); Text("一次搜索多个真实素材库") .foregroundStyle(.secondary) } }
            Text("无需 API Key 也可以先使用 Wikimedia Commons 和 Internet Archive。其他平台的 Key 可现在填写，也可以稍后在“设置”中填写。")
            keyField("Pexels", value: $pexels, link: "https://www.pexels.com/api/")
            keyField("Pixabay", value: $pixabay, link: "https://pixabay.com/api/docs/")
            keyField("YouTube Data API", value: $youtube, link: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")
            HStack { Image(systemName: "lock.shield"); Text("API Key 只保存在本机 macOS Keychain，不写入配置文件或日志。") }.font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("稍后设置") { finish() }; Button("保存并开始") { saveAndFinish() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 650)
    }
    private func keyField(_ name: String, value: Binding<String>, link: String) -> some View {
        HStack { Text(name).frame(width: 140, alignment: .leading); SecureField("可选", text: value).textFieldStyle(.roundedBorder); Link("如何申请", destination: URL(string: link)!) }
    }
    private func saveAndFinish() { try? KeychainService.save(pexels, provider: .pexels); try? KeychainService.save(pixabay, provider: .pixabay); try? KeychainService.save(youtube, provider: .youtube); finish() }
}

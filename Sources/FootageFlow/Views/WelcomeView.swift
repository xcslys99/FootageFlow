import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var localization: LocalizationManager
    let finish: () -> Void
    @State private var pexels = ""
    @State private var pixabay = ""
    @State private var youtube = ""

    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) { Image(systemName: "film.stack").font(.system(size: 42)).foregroundStyle(.tint); VStack(alignment: .leading) { Text(tr("welcome.title")).font(.largeTitle.bold()); Text(tr("welcome.subtitle")).foregroundStyle(.secondary) } }
            Text(tr("welcome.body"))
            keyField("Pexels", value: $pexels, link: "https://www.pexels.com/api/")
            keyField("Pixabay", value: $pixabay, link: "https://pixabay.com/api/docs/")
            keyField("YouTube Data API", value: $youtube, link: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")
            HStack { Image(systemName: "lock.shield"); Text(tr("welcome.security")) }.font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(tr("welcome.later")) { finish() }; Button(tr("welcome.saveStart")) { saveAndFinish() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 650)
    }
    private func keyField(_ name: String, value: Binding<String>, link: String) -> some View {
        HStack { Text(name).frame(width: 140, alignment: .leading); SecureField(tr("welcome.optional"), text: value).textFieldStyle(.roundedBorder); Link(tr("welcome.howToApply"), destination: URL(string: link)!) }
    }
    private func saveAndFinish() { try? KeychainService.save(pexels, provider: .pexels); try? KeychainService.save(pixabay, provider: .pixabay); try? KeychainService.save(youtube, provider: .youtube); finish() }
}

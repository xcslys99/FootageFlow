import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var localization: LocalizationManager
  @EnvironmentObject private var store: DataStore
  @State private var pexelsKey = ""
  @State private var pixabayKey = ""
  @State private var youtubeKey = ""
  @State private var enabled = AppSettings.enabledProviders
  @State private var statuses: [ProviderID: String] = [:]
  @State private var messages: [ProviderID: String] = [:]
  @State private var cacheMessage = ""
  @State private var downloadRoot = AppSettings.downloadRootURL
  @State private var confirmClearHistory = false
  @State private var editingKeys: Set<ProviderID> = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(tr("nav.settings")).font(.largeTitle.bold())
        GroupBox(tr("language.menu")) {
          Picker(
            tr("language.menu"),
            selection: Binding(get: { localization.language }, set: localization.setLanguage)
          ) {
            ForEach(AppLanguage.allCases) { language in Text(language.displayName).tag(language) }
          }
          .pickerStyle(.segmented)
          .padding(8)
        }
        GroupBox(tr("settings.sourcesProviders")) {
          VStack(alignment: .leading, spacing: 0) {
            Text(tr("settings.optionalAPIExplanation"))
              .font(.callout).foregroundStyle(.secondary).padding(10)
            Divider()
            providerCard(
              .pexels, key: $pexelsKey, applyURL: "https://www.pexels.com/api/",
              noKeyDetail: tr("settings.directSearchDetail"))
            Divider()
            providerCard(
              .pixabay, key: $pixabayKey, applyURL: "https://pixabay.com/api/docs/",
              noKeyDetail: tr("settings.directSearchDetail"))
            Divider()
            providerCard(
              .youtube, key: $youtubeKey,
              applyURL: "https://console.cloud.google.com/apis/library/youtube.googleapis.com",
              noKeyDetail: tr("settings.youtubeBestEffortDetail"))
            Divider()
            noKeyRow(.wikimedia, detail: tr("settings.wikimediaDetail"))
            Divider()
            noKeyRow(.internetArchive, detail: tr("settings.archiveDetail"))
          }.padding(6)
        }
        GroupBox(tr("settings.downloadCache")) {
          VStack(alignment: .leading, spacing: 12) {
            LabeledContent(tr("settings.downloadRoot")) {
              HStack {
                Text(downloadRoot.path).lineLimit(1).foregroundStyle(.secondary)
                Button(tr("settings.choose")) { chooseFolder() }
              }
            }
            HStack {
              Button(tr("settings.clearCache")) {
                Task {
                  do {
                    try await SearchCache.shared.clear()
                    await MainActor.run { cacheMessage = tr("settings.cacheCleared") }
                  } catch { await MainActor.run { cacheMessage = tr("settings.cacheFailed") } }
                }
              }
              Text(cacheMessage).foregroundStyle(.secondary)
            }
            Button(tr("settings.clearHistory")) { confirmClearHistory = true }.disabled(
              store.history.isEmpty)
            Button(tr("settings.openLogs")) { DesktopPlatform.shared.open(AppLogger.shared.logURL) }
            Text(tr("settings.logHelp")).font(.caption).foregroundStyle(.secondary)
          }.padding(8)
        }
        GroupBox(tr("settings.privacy")) {
          Text(tr("settings.privacyBody")).font(.callout).padding(8)
        }
      }.padding(24).frame(maxWidth: 900, alignment: .leading)
    }
    .onAppear {
      pexelsKey = KeychainService.read(.pexels)
      pixabayKey = KeychainService.read(.pixabay)
      youtubeKey = KeychainService.read(.youtube)
    }
    .alert(tr("history.clearConfirmTitle"), isPresented: $confirmClearHistory) {
      Button(tr("common.cancel"), role: .cancel) {}
      Button(tr("history.clear"), role: .destructive) { store.clearHistory() }
    } message: {
      Text(tr("history.clearConfirmBody"))
    }
  }

  private func providerCard(
    _ provider: ProviderID, key: Binding<String>, applyURL: String, noKeyDetail: String
  ) -> some View {
    let hasKey = !key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let mode = ProviderFactory.make(provider, apiKey: hasKey ? key.wrappedValue : "").info.mode
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Toggle("", isOn: enabledBinding(provider)).labelsHidden()
        Text(provider.displayName).font(.headline)
        Spacer()
        Text(mode.label).font(.caption.bold())
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(modeColor(mode).opacity(0.14), in: Capsule())
        if hasKey && provider != .youtube {
          Label(tr("settings.recommended"), systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(.green)
        } else if !hasKey {
          Text(tr("provider.bestEffort")).font(.caption).foregroundStyle(.blue)
        }
      }
      if hasKey && !editingKeys.contains(provider) {
        HStack {
          Text(tr("settings.apiKey")).foregroundStyle(.secondary)
          Text("••••••••••••").font(.system(.body, design: .monospaced))
          Button(tr("settings.changeAPIKey")) { editingKeys.insert(provider) }
          Button(tr("settings.removeAPIKey"), role: .destructive) { removeKey(provider, key: key) }
          Button(tr("settings.testConnection")) { test(provider, key: key.wrappedValue) }
          Link(tr("welcome.howToApply"), destination: URL(string: applyURL)!)
        }
      } else {
        Text(hasKey ? tr("settings.replaceKeyDetail") : noKeyDetail)
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          SecureField(tr("settings.apiKeyOptional"), text: key).textFieldStyle(.roundedBorder)
          Button(hasKey ? tr("common.save") : tr("settings.addAPIKey")) {
            saveKey(provider, value: key.wrappedValue)
            editingKeys.remove(provider)
          }.disabled(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if hasKey {
            Button(tr("common.cancel")) {
              key.wrappedValue = KeychainService.read(provider)
              editingKeys.remove(provider)
            }
          }
          Button(tr("settings.testDirectSearch")) { test(provider, key: "") }
          Link(tr("welcome.howToApply"), destination: URL(string: applyURL)!)
        }
      }
      if let status = statuses[provider] {
        HStack {
          Text(status).foregroundStyle(statusColor(status))
          if let message = messages[provider] { Text(message).foregroundStyle(.secondary) }
        }.font(.caption)
      }
    }.padding(.vertical, 10)
  }

  private func noKeyRow(_ provider: ProviderID, detail: String) -> some View {
    HStack {
      Toggle("", isOn: enabledBinding(provider)).labelsHidden()
      VStack(alignment: .leading) {
        Text(provider.displayName).font(.headline)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text(statuses[provider] ?? tr("settings.enabled")).foregroundStyle(
        statuses[provider] == tr("settings.connectionFailed") ? .red : .green)
      Button(tr("settings.testConnection")) { test(provider, key: "") }
    }.padding(.vertical, 10)
  }

  private func enabledBinding(_ provider: ProviderID) -> Binding<Bool> {
    Binding(
      get: { enabled.contains(provider) },
      set: { value in
        if value { enabled.insert(provider) } else { enabled.remove(provider) }
        AppSettings.enabledProviders = enabled
      })
  }
  private func saveKey(_ provider: ProviderID, value: String) {
    do {
      try KeychainService.save(
        value.trimmingCharacters(in: .whitespacesAndNewlines), provider: provider)
      statuses[provider] = value.isEmpty ? tr("settings.notConfigured") : tr("settings.configured")
      messages[provider] = tr("settings.savedKeychain")
    } catch {
      statuses[provider] = tr("settings.saveFailed")
      messages[provider] = error.localizedDescription
    }
  }
  private func removeKey(_ provider: ProviderID, key: Binding<String>) {
    do {
      try KeychainService.save("", provider: provider)
      key.wrappedValue = ""
      editingKeys.remove(provider)
      statuses[provider] = tr("settings.notConfigured")
      messages[provider] = tr("settings.directSearchEnabled")
    } catch {
      statuses[provider] = tr("settings.saveFailed")
      messages[provider] = error.localizedDescription
    }
  }
  private func test(_ provider: ProviderID, key: String) {
    statuses[provider] = tr("settings.connecting")
    messages[provider] = nil
    Task {
      let source = ProviderFactory.make(provider, apiKey: key)
      do {
        try await source.testConnection()
        await MainActor.run { statuses[provider] = tr("settings.connectionSuccess") }
      } catch {
        await MainActor.run {
          statuses[provider] = tr("settings.connectionFailed")
          messages[provider] = error.localizedDescription
        }
      }
    }
  }
  private func chooseFolder() {
    if let url = DesktopPlatform.shared.chooseDirectory(prompt: tr("settings.chooseDownloadFolder"))
    {
      downloadRoot = url
      AppSettings.downloadRootURL = url
    }
  }
  private func statusColor(_ status: String?) -> Color {
    status == tr("settings.connectionSuccess")
      ? .green
      : (status == tr("settings.connectionFailed") || status == tr("settings.saveFailed")
        ? .red : .secondary)
  }
  private func modeColor(_ mode: ProviderMode) -> Color {
    switch mode {
    case .officialAPI: .green
    case .publicInterface: .teal
    case .directSearch, .ytDLP: .blue
    }
  }
}

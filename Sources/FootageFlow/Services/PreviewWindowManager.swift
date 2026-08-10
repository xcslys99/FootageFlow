import AVKit
import AppKit
import Combine
import Foundation

@MainActor
final class PreviewWindowManager {
  static let shared = PreviewWindowManager()
  private var controllers: [ObjectIdentifier: PreviewWindowController] = [:]

  func show(_ asset: MediaAsset) {
    let controller = PreviewWindowController(asset: asset) { [weak self] controller in
      self?.controllers.removeValue(forKey: ObjectIdentifier(controller))
    }
    controllers[ObjectIdentifier(controller)] = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor
private final class PreviewWindowController: NSWindowController, NSWindowDelegate {
  private let asset: MediaAsset
  private let onClose: (PreviewWindowController) -> Void
  private var player: AVPlayer?
  private var imageTask: Task<Void, Never>?
  private var sourceButton: NSButton?
  private var subtitleField: NSTextField?
  private var descriptionField: NSTextField?
  private var localizationCancellable: AnyCancellable?

  init(asset: MediaAsset, onClose: @escaping (PreviewWindowController) -> Void) {
    self.asset = asset
    self.onClose = onClose
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false
    )
    window.title = asset.title
    window.minSize = NSSize(width: 680, height: 460)
    window.center()
    super.init(window: window)
    window.delegate = self
    window.contentView = buildContent()
    localizationCancellable = LocalizationManager.shared.$language.sink { [weak self] _ in
      DispatchQueue.main.async { self?.refreshLocalizedText() }
    }
  }

  required init?(coder: NSCoder) { nil }

  private func buildContent() -> NSView {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: asset.title)
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    title.lineBreakMode = .byTruncatingTail
    let subtitle = NSTextField(
      labelWithString:
        "\(asset.provider.displayName) · \(asset.resolutionText) · \(asset.durationText) · \(asset.licenseText)"
    )
    subtitle.textColor = .secondaryLabelColor
    subtitle.font = .systemFont(ofSize: 12)
    subtitleField = subtitle
    let header = NSStackView(views: [title, subtitle])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 4
    let sourceButton = NSButton(
      title: tr("media.openSource"), target: self, action: #selector(openSource))
    sourceButton.bezelStyle = .rounded
    self.sourceButton = sourceButton
    let top = NSStackView(views: [header, NSView(), sourceButton])
    top.orientation = .horizontal
    top.alignment = .centerY
    top.spacing = 12

    let content: NSView
    if asset.mediaType == .video, let url = try? URLValidator.remote(asset.previewURL) {
      let playerView = AVPlayerView()
      playerView.controlsStyle = .floating
      playerView.videoGravity = .resizeAspect
      let player = AVPlayer(url: url)
      playerView.player = player
      self.player = player
      player.play()
      content = playerView
    } else {
      let imageView = NSImageView()
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.imageAlignment = .alignCenter
      imageView.wantsLayer = true
      imageView.layer?.backgroundColor = NSColor.black.cgColor
      if let url = try? URLValidator.remote(asset.previewURL ?? asset.thumbnailURL) {
        imageTask = Task {
          guard let (data, _) = try? await URLSession.shared.data(from: url),
            let image = NSImage(data: data), !Task.isCancelled
          else { return }
          imageView.image = image
        }
      }
      content = imageView
    }

    let description = NSTextField(
      wrappingLabelWithString: asset.description ?? tr("media.noDescription"))
    descriptionField = description
    description.maximumNumberOfLines = 2
    description.textColor = .secondaryLabelColor
    for view in [top, content, description] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
      top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
      top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
      content.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
      content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
      content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
      description.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 10),
      description.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
      description.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
      description.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
    ])
    return root
  }

  @objc private func openSource() {
    guard let url = try? URLValidator.remote(asset.sourcePageURL) else { return }
    NSWorkspace.shared.open(url)
  }
  private func refreshLocalizedText() {
    sourceButton?.title = tr("media.openSource")
    subtitleField?.stringValue =
      "\(asset.provider.displayName) · \(asset.resolutionText) · \(asset.durationText) · \(asset.licenseText)"
    if asset.description == nil { descriptionField?.stringValue = tr("media.noDescription") }
  }
  func windowWillClose(_ notification: Notification) {
    player?.pause()
    player = nil
    imageTask?.cancel()
    localizationCancellable?.cancel()
    onClose(self)
  }
}

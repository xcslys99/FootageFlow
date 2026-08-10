import AppKit
import AVKit
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

    init(asset: MediaAsset, onClose: @escaping (PreviewWindowController) -> Void) {
        self.asset = asset; self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = asset.title; window.minSize = NSSize(width: 680, height: 460); window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent() -> NSView {
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: asset.title); title.font = .systemFont(ofSize: 16, weight: .semibold); title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: "\(asset.provider.displayName) · \(asset.resolutionText) · \(asset.durationText) · \(asset.licenseText)"); subtitle.textColor = .secondaryLabelColor; subtitle.font = .systemFont(ofSize: 12)
        let header = NSStackView(views: [title, subtitle]); header.orientation = .vertical; header.alignment = .leading; header.spacing = 4
        let sourceButton = NSButton(title: "打开来源", target: self, action: #selector(openSource)); sourceButton.bezelStyle = .rounded
        let top = NSStackView(views: [header, NSView(), sourceButton]); top.orientation = .horizontal; top.alignment = .centerY; top.spacing = 12

        let content: NSView
        if asset.mediaType == .video, let url = try? URLValidator.remote(asset.previewURL) {
            let playerView = AVPlayerView(); playerView.controlsStyle = .floating; playerView.videoGravity = .resizeAspect
            let player = AVPlayer(url: url); playerView.player = player; self.player = player; player.play(); content = playerView
        } else {
            let imageView = NSImageView(); imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.imageAlignment = .alignCenter
            imageView.wantsLayer = true; imageView.layer?.backgroundColor = NSColor.black.cgColor
            if let url = try? URLValidator.remote(asset.previewURL ?? asset.thumbnailURL) {
                imageTask = Task {
                    guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data), !Task.isCancelled else { return }
                    imageView.image = image
                }
            }
            content = imageView
        }

        let description = NSTextField(wrappingLabelWithString: asset.description ?? "暂无描述。请在发布前查看原始来源页确认内容与授权。")
        description.maximumNumberOfLines = 2; description.textColor = .secondaryLabelColor
        [top, content, description].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12), content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            description.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 10), description.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), description.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), description.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        return root
    }

    @objc private func openSource() {
        guard let url = try? URLValidator.remote(asset.sourcePageURL) else { return }
        NSWorkspace.shared.open(url)
    }
    func windowWillClose(_ notification: Notification) { player?.pause(); player = nil; imageTask?.cancel(); onClose(self) }
}

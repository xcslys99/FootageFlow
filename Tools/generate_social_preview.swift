import AppKit

let canvasSize = NSSize(width: 1280, height: 640)
let sourceURL = URL(fileURLWithPath: "docs/images/research-mode-v090.png")
let outputURL = URL(fileURLWithPath: "docs/images/social-preview.png")

guard let screenshot = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load \(sourceURL.path)\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
let context = graphicsContext.cgContext

let background = NSColor(calibratedRed: 0.055, green: 0.094, blue: 0.16, alpha: 1)
background.setFill()
context.fill(CGRect(origin: .zero, size: canvasSize))

let accent = NSColor(calibratedRed: 0.19, green: 0.46, blue: 0.98, alpha: 1)
accent.setFill()
context.fill(CGRect(x: 0, y: 0, width: 8, height: canvasSize.height))

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, lineSpacing: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

let white = NSColor.white
drawText("FootageFlow", in: NSRect(x: 64, y: 506, width: 440, height: 64), font: .systemFont(ofSize: 48, weight: .bold), color: white)
drawText(
    "Search footage.\nResearch sources.\nDownload media.",
    in: NSRect(x: 64, y: 294, width: 460, height: 195),
    font: .systemFont(ofSize: 36, weight: .bold),
    color: white,
    lineSpacing: 8
)
drawText("FREE & OPEN SOURCE", in: NSRect(x: 64, y: 187, width: 320, height: 28), font: .systemFont(ofSize: 18, weight: .bold), color: NSColor(calibratedRed: 0.61, green: 0.78, blue: 1, alpha: 1))
drawText("macOS + Windows", in: NSRect(x: 64, y: 129, width: 360, height: 38), font: .systemFont(ofSize: 29, weight: .semibold), color: NSColor(calibratedWhite: 0.9, alpha: 1))
drawText("Search • Research • Best-effort downloads", in: NSRect(x: 64, y: 90, width: 455, height: 24), font: .systemFont(ofSize: 15, weight: .medium), color: NSColor(calibratedWhite: 0.7, alpha: 1))

let screenshotRect = NSRect(x: 544, y: 85, width: 692, height: 431)
let shadowRect = screenshotRect.insetBy(dx: -4, dy: -4)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.42).cgColor)
NSColor.white.setFill()
NSBezierPath(roundedRect: shadowRect, xRadius: 17, yRadius: 17).fill()
context.restoreGState()

context.saveGState()
NSBezierPath(roundedRect: screenshotRect, xRadius: 13, yRadius: 13).addClip()
screenshot.draw(in: screenshotRect, from: NSRect(origin: .zero, size: screenshot.size), operation: .sourceOver, fraction: 1)
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode social preview\n", stderr)
    exit(1)
}
try png.write(to: outputURL)
print("Wrote \(outputURL.path)")

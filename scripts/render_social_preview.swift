#!/usr/bin/env swift

import AppKit
import Foundation

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let quickSearchURL = repositoryRoot.appendingPathComponent("docs/images/quick-search-v0121.png")
private let workspaceURL = repositoryRoot.appendingPathComponent("docs/images/workspace-smart-collections-v0121.png")
private let iconURL = repositoryRoot.appendingPathComponent(".build/icon-1024.png")
private let outputURL = repositoryRoot.appendingPathComponent("docs/images/social-preview-v0121.png")

private func image(at url: URL) -> NSImage {
  guard let image = NSImage(contentsOf: url) else {
    fputs("Unable to read \(url.path)\n", stderr)
    exit(1)
  }
  return image
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func drawText(
  _ text: String,
  at point: NSPoint,
  font: NSFont,
  color: NSColor,
  width: CGFloat = 460,
  lineHeight: CGFloat? = nil
) {
  let paragraph = NSMutableParagraphStyle()
  let effectiveLineHeight = lineHeight ?? ceil(font.pointSize * 1.25)
  if let lineHeight {
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
  }
  let textHeight = effectiveLineHeight * CGFloat(text.split(separator: "\n", omittingEmptySubsequences: false).count)
  (text as NSString).draw(
    in: NSRect(x: point.x, y: point.y, width: width, height: textHeight),
    withAttributes: [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ])
}

private func drawScreenshot(_ image: NSImage, in rect: NSRect, radius: CGFloat, alpha: CGFloat = 1) {
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
  shadow.shadowBlurRadius = 24
  shadow.shadowOffset = NSSize(width: 0, height: -8)
  shadow.set()
  color(255, 255, 255, alpha: 0.12).setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
  NSGraphicsContext.restoreGraphicsState()

  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
  image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
  NSGraphicsContext.restoreGraphicsState()

  color(255, 255, 255, alpha: 0.18).setStroke()
  let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  border.lineWidth = 1
  border.stroke()
}

let canvasSize = NSSize(width: 1280, height: 640)
let canvas = NSImage(size: canvasSize)
canvas.lockFocus()

let background = NSGradient(colors: [color(15, 27, 49), color(20, 34, 60)])!
background.draw(in: NSRect(origin: .zero, size: canvasSize), angle: 0)
color(45, 141, 255).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 10, height: 640)).fill()

let icon = image(at: iconURL)
icon.draw(in: NSRect(x: 62, y: 513, width: 64, height: 64))
drawText("FootageFlow", at: NSPoint(x: 143, y: 515), font: .boldSystemFont(ofSize: 45), color: .white)

drawText(
  "Search footage.\nPaste links.\nDownload media.",
  at: NSPoint(x: 62, y: 278),
  font: .boldSystemFont(ofSize: 43),
  color: .white,
  lineHeight: 58
)

let badgeRect = NSRect(x: 62, y: 218, width: 114, height: 34)
color(45, 141, 255, alpha: 0.20).setFill()
NSBezierPath(roundedRect: badgeRect, xRadius: 17, yRadius: 17).fill()
drawText("v0.12.1", at: NSPoint(x: 84, y: 223), font: .boldSystemFont(ofSize: 17), color: color(131, 194, 255))

drawText("FREE & OPEN SOURCE", at: NSPoint(x: 62, y: 157), font: .boldSystemFont(ofSize: 17), color: color(137, 196, 255))
drawText("macOS + Windows", at: NSPoint(x: 62, y: 106), font: .boldSystemFont(ofSize: 28), color: color(236, 242, 251))
drawText(
  "Multi-source search  •  Best-effort link downloader",
  at: NSPoint(x: 62, y: 68),
  font: .systemFont(ofSize: 15, weight: .medium),
  color: color(171, 185, 207)
)

let workspace = image(at: workspaceURL)
let quickSearch = image(at: quickSearchURL)
drawScreenshot(workspace, in: NSRect(x: 684, y: 263, width: 540, height: 344), radius: 15, alpha: 0.96)
drawScreenshot(quickSearch, in: NSRect(x: 518, y: 50, width: 706, height: 450), radius: 17)

canvas.unlockFocus()

guard
  let tiff = canvas.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fputs("Unable to encode social preview\n", stderr)
  exit(1)
}

try png.write(to: outputURL, options: .atomic)
print(outputURL.path)

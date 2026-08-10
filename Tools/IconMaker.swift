import AppKit

guard CommandLine.arguments.count > 1 else { exit(2) }
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let bounds = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.055, green: 0.11, blue: 0.22, alpha: 1).setFill()
NSBezierPath(roundedRect: bounds.insetBy(dx: 52, dy: 52), xRadius: 210, yRadius: 210).fill()

let panel = NSRect(x: 190, y: 250, width: 550, height: 500)
NSColor(calibratedRed: 0.12, green: 0.54, blue: 0.96, alpha: 1).setFill()
NSBezierPath(roundedRect: panel, xRadius: 62, yRadius: 62).fill()
NSColor.white.withAlphaComponent(0.92).setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 318, width: 430, height: 364), xRadius: 28, yRadius: 28).fill()

NSColor(calibratedRed: 0.055, green: 0.11, blue: 0.22, alpha: 0.82).setFill()
for y in stride(from: 290.0, through: 670.0, by: 95.0) {
    NSBezierPath(roundedRect: NSRect(x: 205, y: y, width: 32, height: 50), xRadius: 8, yRadius: 8).fill()
    NSBezierPath(roundedRect: NSRect(x: 693, y: y, width: 32, height: 50), xRadius: 8, yRadius: 8).fill()
}

let glass = NSBezierPath(ovalIn: NSRect(x: 500, y: 420, width: 275, height: 275))
NSColor(calibratedRed: 1, green: 0.77, blue: 0.18, alpha: 1).setStroke()
glass.lineWidth = 58; glass.stroke()
let handle = NSBezierPath(); handle.move(to: NSPoint(x: 705, y: 465)); handle.line(to: NSPoint(x: 855, y: 315)); handle.lineCapStyle = .round; handle.lineWidth = 66; handle.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
try png.write(to: URL(fileURLWithPath: output), options: .atomic)

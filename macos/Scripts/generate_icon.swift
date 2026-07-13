import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create bitmap context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
defer { NSGraphicsContext.restoreGraphicsState() }
let context = graphics.cgContext

let bounds = NSRect(origin: .zero, size: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 26, dy: 26), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.025, green: 0.028, blue: 0.040, alpha: 1).setFill()
background.fill()

let colors = [
    NSColor(calibratedRed: 0.49, green: 0.38, blue: 0.98, alpha: 0.95),
    NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.72, alpha: 0.95)
]
NSGradient(colors: colors)?.draw(in: bounds.insetBy(dx: 78, dy: 78), angle: -48)

let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: 120, dy: 120), xRadius: 155, yRadius: 155)
NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.055, alpha: 0.92).setFill()
inner.fill()

context.saveGState()
context.setShadow(offset: .zero, blur: 42, color: NSColor(calibratedRed: 0.48, green: 0.36, blue: 1, alpha: 0.65).cgColor)
let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 218, dy: 218))
ring.lineWidth = 42
NSColor(calibratedRed: 0.49, green: 0.38, blue: 1, alpha: 1).setStroke()
ring.stroke()
context.restoreGState()

let satelliteRadius: CGFloat = 32
for angle in stride(from: 0.0, to: 360.0, by: 120.0) {
    let radians = angle * .pi / 180
    let center = NSPoint(x: 512 + cos(radians) * 294, y: 512 + sin(radians) * 294)
    let dot = NSBezierPath(ovalIn: NSRect(
        x: center.x - satelliteRadius,
        y: center.y - satelliteRadius,
        width: satelliteRadius * 2,
        height: satelliteRadius * 2
    ))
    NSColor(calibratedRed: 0.59, green: 0.48, blue: 1, alpha: 1).setFill()
    dot.fill()
}

let check = NSBezierPath()
check.move(to: NSPoint(x: 342, y: 520))
check.line(to: NSPoint(x: 462, y: 390))
check.line(to: NSPoint(x: 700, y: 666))
check.lineWidth = 66
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)

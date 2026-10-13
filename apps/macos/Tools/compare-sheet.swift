// Side-by-side comparison of a released v0.4.20 reference and a native screenshot.
// Usage: swift Tools/compare-sheet.swift <legacy.png> <native.png> <out.png> <caption>
import AppKit

let args = CommandLine.arguments
guard args.count >= 5,
      let legacy = NSImage(contentsOfFile: args[1]),
      let native = NSImage(contentsOfFile: args[2]) else {
    FileHandle.standardError.write("usage: compare-sheet legacy.png native.png out.png caption\n".data(using: .utf8)!)
    exit(1)
}

func pixelSize(_ image: NSImage) -> CGSize {
    guard let rep = image.representations.first else { return image.size }
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

let height: CGFloat = 1000
let gap: CGFloat = 40
let header: CGFloat = 90
let legacySize = pixelSize(legacy)
let nativeSize = pixelSize(native)
let legacyWidth = legacySize.width * height / legacySize.height
let nativeWidth = nativeSize.width * height / nativeSize.height
let canvas = CGSize(width: legacyWidth + nativeWidth + gap * 3, height: height + header + gap)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.5, alpha: 1).setFill()
NSRect(origin: .zero, size: canvas).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    .foregroundColor: NSColor.white,
]
("v0.4.20 · " + args[4]).draw(at: NSPoint(x: gap, y: height + gap + 22), withAttributes: attributes)
("SwiftUI · Liquid Glass").draw(at: NSPoint(x: gap * 2 + legacyWidth, y: height + gap + 22), withAttributes: attributes)
legacy.draw(in: NSRect(x: gap, y: gap / 2, width: legacyWidth, height: height))
native.draw(in: NSRect(x: gap * 2 + legacyWidth, y: gap / 2, width: nativeWidth, height: height))
NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: args[3]))

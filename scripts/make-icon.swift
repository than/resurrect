#!/usr/bin/env swift
// Generate Resurrect's app iconset from the 🧟 glyph on a dark rounded tile.
// Usage: swift scripts/make-icon.swift <outIconsetDir>
// Then:  iconutil -c icns <outIconsetDir> -o icon/Resurrect.icns
import AppKit

let emoji = "\u{1F9DF}"  // 🧟
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resurrect.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded dark tile (squircle-ish), leaving a little canvas padding.
    let inset = size * 0.055
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = size * 0.22
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.12, alpha: 1).setFill()
    tile.fill()

    // Centered zombie glyph.
    let fontSize = size * 0.60
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
    let str = emoji as NSString
    let s = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote iconset to \(outDir)")

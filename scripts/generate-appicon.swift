#!/usr/bin/env swift
//
//  generate-appicon.swift
//
//  Build-time tooling (not product code): renders suzu's app icon - a white
//  bell on a calm teal squircle - at every macOS size into the asset catalog's
//  AppIcon.appiconset. Re-run after changing the look:
//
//      swift scripts/generate-appicon.swift
//

import AppKit

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Suzu/Assets.xcassets/AppIcon.appiconset"

let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.092
    let content = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = content.width * 0.2237
    let squircle = NSBezierPath(roundedRect: content, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.79, blue: 0.79, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.53, blue: 0.56, alpha: 1),
    ])
    gradient?.draw(in: squircle, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: content.width * 0.5, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let bell = tinted(symbol, .white)
        let drawRect = NSRect(
            x: content.midX - bell.size.width / 2,
            y: content.midY - bell.size.height / 2,
            width: bell.size.width, height: bell.size.height
        )
        bell.draw(in: drawRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

for px in pixelSizes {
    let data = render(px)
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(px).png")
    try! data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

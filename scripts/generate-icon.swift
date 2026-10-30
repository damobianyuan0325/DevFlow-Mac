#!/usr/bin/env swift
// Original DevFlow brand asset. Geometry mirrors assets/DevFlow.svg.
// Run from the repository with:
// swift -module-cache-path .build/icon-module-cache scripts/generate-icon.swift
// Uses only local AppKit/CoreGraphics. No network, fonts or external dependencies.
import AppKit
import Foundation

let sourceURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let root = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("assets", isDirectory: true)
let work = root.appendingPathComponent(".build/icon-assets", isDirectory: true)
let iconset = work.appendingPathComponent("DevFlow.iconset", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255, alpha
    ])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

func renderIcon(size: Int) throws -> CGImage {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "DevFlow.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap."])
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)

    let tile = roundedRect(CGRect(x: 96, y: 96, width: 832, height: 832), radius: 188)
    context.saveGState()
    // Quartz shadow dimensions are device-space values, unlike the path geometry.
    context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 34 * scale, color: color(0x001511, alpha: 0.22))
    context.addPath(tile)
    context.setFillColor(color(0x0C322E))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(gradient([color(0x174A40), color(0x0C322E), color(0x082321)], locations: [0, 0.56, 1]),
                               start: CGPoint(x: 96, y: 96), end: CGPoint(x: 928, y: 928), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.drawRadialGradient(gradient([color(0x68D5AA, alpha: 0.13), color(0x68D5AA, alpha: 0)], locations: [0, 1]),
                               startCenter: CGPoint(x: 312, y: 180), startRadius: 0,
                               endCenter: CGPoint(x: 312, y: 180), endRadius: 699, options: [.drawsAfterEndLocation])
    context.restoreGState()

    context.addPath(roundedRect(CGRect(x: 98, y: 98, width: 828, height: 828), radius: 186))
    context.setStrokeColor(color(0xA8E7CB, alpha: 0.16))
    context.setLineWidth(2)
    context.strokePath()

    let route = CGMutablePath()
    route.move(to: CGPoint(x: 326, y: 310))
    route.addLine(to: CGPoint(x: 508, y: 310))
    route.addCurve(to: CGPoint(x: 722, y: 512), control1: CGPoint(x: 648, y: 310), control2: CGPoint(x: 722, y: 398))
    route.addCurve(to: CGPoint(x: 508, y: 714), control1: CGPoint(x: 722, y: 626), control2: CGPoint(x: 648, y: 714))
    route.addLine(to: CGPoint(x: 350, y: 714))
    route.addCurve(to: CGPoint(x: 326, y: 690), control1: CGPoint(x: 336.745, y: 714), control2: CGPoint(x: 326, y: 703.255))
    route.addLine(to: CGPoint(x: 326, y: 536))
    route.addCurve(to: CGPoint(x: 350, y: 512), control1: CGPoint(x: 326, y: 522.745), control2: CGPoint(x: 336.745, y: 512))
    route.addLine(to: CGPoint(x: 542, y: 512))
    let stroked = route.copy(strokingWithWidth: 74, lineCap: .round, lineJoin: .round, miterLimit: 1)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 20 * scale, color: color(0x001B15, alpha: 0.28))
    context.addPath(stroked)
    context.setFillColor(color(0x91EBCB))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(stroked)
    context.clip()
    context.drawLinearGradient(gradient([color(0xD9FBE7), color(0x91EBCB), color(0x42CFA7)], locations: [0, 0.46, 1]),
                               start: CGPoint(x: 326, y: 310), end: CGPoint(x: 643, y: 714), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    context.setFillColor(color(0xD9FBE7))
    context.fillEllipse(in: CGRect(x: 277, y: 261, width: 98, height: 98))
    context.setFillColor(color(0x0C342E))
    context.fillEllipse(in: CGRect(x: 492, y: 454, width: 116, height: 116))
    context.setStrokeColor(color(0xC0F6DD))
    context.setLineWidth(19)
    context.strokeEllipse(in: CGRect(x: 492, y: 454, width: 116, height: 116))

    guard let image = context.makeImage() else { throw NSError(domain: "DevFlow.Icon", code: 2) }
    return image
}

func writePNG(_ image: CGImage, at url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DevFlow.Icon", code: 3)
    }
    try data.write(to: url, options: .atomic)
}

let full = try renderIcon(size: 1024)
try writePNG(full, at: assets.appendingPathComponent("DevFlow.png"))
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(renderIcon(size: pixels), at: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}

// Modern ICNS stores PNG representations in typed, length-prefixed chunks.
// Write the container directly so generation also works when iconutil's encoder
// is unavailable in a restricted environment. Every representation is rendered
// above from the same vector geometry, including the Retina-specific sizes.
func bigEndian(_ value: UInt32) -> Data {
    var number = value.bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let representations: [(String, String, Int)] = [
    ("icp4", "icon_16x16.png", 16), ("ic11", "icon_16x16@2x.png", 32),
    ("icp5", "icon_32x32.png", 32), ("ic12", "icon_32x32@2x.png", 64),
    ("ic07", "icon_128x128.png", 128), ("ic13", "icon_128x128@2x.png", 256),
    ("ic08", "icon_256x256.png", 256), ("ic14", "icon_256x256@2x.png", 512),
    ("ic09", "icon_512x512.png", 512), ("ic10", "icon_512x512@2x.png", 1024)
]
var chunks = Data()
for (type, filename, pixels) in representations {
    let data = try Data(contentsOf: iconset.appendingPathComponent(filename))
    guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide == pixels, bitmap.pixelsHigh == pixels else {
        throw NSError(domain: "DevFlow.Icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid representation: \(filename)"])
    }
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(UInt32(data.count + 8)))
    chunks.append(data)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(UInt32(chunks.count + 8)))
icns.append(chunks)
let iconURL = assets.appendingPathComponent("DevFlow.icns")
try icns.write(to: iconURL, options: .atomic)
guard let nativeIcon = NSImage(contentsOf: iconURL), nativeIcon.isValid else {
    throw NSError(domain: "DevFlow.Icon", code: 5, userInfo: [NSLocalizedDescriptionKey: "AppKit could not decode the generated ICNS."])
}

// Contact sheet uses the exact generated images at native pixel sizes for small-size QA.
let previewWidth = 1200, previewHeight = 400
let preview = CGContext(data: nil, width: previewWidth, height: previewHeight, bitsPerComponent: 8,
                        bytesPerRow: previewWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
preview.setFillColor(color(0xE9EEEA))
preview.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
preview.setFillColor(color(0x181E1C))
preview.fill(CGRect(x: 600, y: 0, width: 600, height: 400))
for offset in [0, 600] {
    var x = CGFloat(offset + 26)
    for size in [256, 128, 64, 32, 16] {
        preview.draw(try renderIcon(size: size), in: CGRect(x: x, y: CGFloat((400 - size) / 2), width: CGFloat(size), height: CGFloat(size)))
        x += CGFloat(size + 18)
    }
}
try writePNG(preview.makeImage()!, at: assets.appendingPathComponent("DevFlow-preview.png"))
print("Generated assets/DevFlow.png (1024 RGBA), assets/DevFlow.icns (16–1024 px) and assets/DevFlow-preview.png.")

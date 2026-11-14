// Builds the app icon from the bishop's idle frame: a midnight-blue squircle with a soft golden
// halo glow behind him. Writes an .iconset and converts it to .icns with iconutil.
//
// usage: swift tools/make-icon.swift <bishop.png> <out.icns>
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("usage: make-icon.swift <bishop.png> <out.icns>"); exit(1)
}

// Idle row, first frame (176×200 cells, see SpriteSheet.bishop).
let cellW = 176, cellH = 200
let frame = sheet.cropping(to: CGRect(x: 0, y: cellH, width: cellW, height: cellH))!

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    // macOS icon grid: 824/1024 body, centered, corner radius ~185/1024.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * 185 / 1024
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle); ctx.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()

    // Midnight-blue vertical gradient (contrasts with his burgundy cape and gold halo).
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        CGColor(red: 0.17, green: 0.25, blue: 0.47, alpha: 1),
        CGColor(red: 0.06, green: 0.09, blue: 0.21, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Golden glow behind the head.
    let glowCenter = CGPoint(x: s / 2, y: body.minY + body.height * 0.66)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        CGColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 0.55),
        CGColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter,
                           endRadius: body.width * 0.48, options: [])

    // The bishop, scaled so his head and shoulders fill the frame; feet run off the bottom edge.
    let figureH = body.height * 1.18
    let figureW = figureH * CGFloat(cellW) / CGFloat(cellH)
    let figure = CGRect(x: (s - figureW) / 2 + body.width * 0.02, y: body.minY - figureH * 0.24,
                        width: figureW, height: figureH)
    ctx.setShadow(offset: .zero, blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.4))
    ctx.draw(frame, in: figure)
    ctx.restoreGState()

    // Subtle inner rim.
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.25))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: args[2])
let iconset = out.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let dest = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL,
                                                   UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(size: base * scale), nil)
        CGImageDestinationFinalize(dest)
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
try? FileManager.default.removeItem(at: iconset)
print("wrote \(out.path)")

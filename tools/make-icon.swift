// Builds the app icon: a pixel-art mountain under a golden halo, on a midnight-blue squircle.
// The scene is a 32×32 grid drawn as hard-edged blocks (to match the pixel-art patrons), rendered
// at 1024 px and scaled down for the smaller sizes. Writes an .iconset and converts it with iconutil.
//
// usage: swift tools/make-icon.swift <out.icns>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    print("usage: make-icon.swift <out.icns>"); exit(1)
}

typealias RGB = (r: Int, g: Int, b: Int)
let skyTop: RGB = (22, 34, 72), skyBottom: RGB = (58, 88, 140)
let star: RGB = (200, 214, 240)
let gold: RGB = (232, 193, 90)
let farPeak: RGB = (28, 42, 80)
let rockLit: RGB = (112, 128, 168), rockShade: RGB = (72, 88, 128)
let snowLit: RGB = (243, 245, 250), snowShade: RGB = (196, 208, 230)
let hills: RGB = (20, 32, 62)

let grid = 32

/// Colour of grid cell (x, y), y growing downward.
func cell(_ x: Int, _ y: Int) -> RGB {
    let fx = Double(x) + 0.5, fy = Double(y) + 0.5

    // Foreground hills.
    if fy > 27 + 1.2 * sin(fx / 3.2) { return hills }

    // Main peak: apex at (16, 9), slope 1; lit on the left, shaded on the right.
    let apexX = 16.0, apexY = 9.0
    let half = fy - apexY
    if half >= 0 && abs(fx - apexX) <= half + 0.5 {
        let lit = fx <= apexX
        let snowLine = apexY + 5 + (x % 3 == 0 ? 1 : 0) + (x % 5 == 1 ? -1 : 0)  // jagged edge
        if fy < snowLine { return lit ? snowLit : snowShade }
        return lit ? rockLit : rockShade
    }

    // Flanking peaks behind.
    if fy > 15 + abs(fx - 6) * 1.1 || fy > 14 + abs(fx - 27) * 1.0 { return farPeak }

    // Halo over the summit.
    let hx = (fx - 16) / 5.0, hy = (fy - 4.5) / 1.8
    if abs(sqrt(hx * hx + hy * hy) - 1) < 0.22 { return gold }

    // A few stars, then the sky gradient in coarse bands.
    if [(4, 3), (26, 5), (9, 8), (29, 10), (22, 2), (2, 11)].contains(where: { $0 == (x, y) }) { return star }
    let t = Double(y / 4) / Double(grid / 4)
    return (skyTop.r + Int(Double(skyBottom.r - skyTop.r) * t),
            skyTop.g + Int(Double(skyBottom.g - skyTop.g) * t),
            skyTop.b + Int(Double(skyBottom.b - skyTop.b) * t))
}

func color(_ c: RGB) -> CGColor {
    CGColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
}

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func renderMaster() -> CGImage {
    let s = 1024.0
    let ctx = context(1024)
    // macOS icon grid: 824/1024 body, centered, corner radius ~185/1024.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = CGPath(roundedRect: body, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle); ctx.setFillColor(color(hills)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let step = body.width / Double(grid)
    for y in 0..<grid {
        for x in 0..<grid {
            // Round cell edges so neighbouring blocks share exact boundaries (no seams).
            let x0 = (body.minX + Double(x) * step).rounded(), x1 = (body.minX + Double(x + 1) * step).rounded()
            let top = (body.maxY - Double(y) * step).rounded(), bottom = (body.maxY - Double(y + 1) * step).rounded()
            ctx.setFillColor(color(cell(x, y)))
            ctx.fill(CGRect(x: x0, y: bottom, width: x1 - x0, height: top - bottom))
        }
    }
    ctx.restoreGState()

    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.25))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()
    return ctx.makeImage()!
}

let master = renderMaster()
func render(size: Int) -> CGImage {
    if size == 1024 { return master }
    let ctx = context(size)
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
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

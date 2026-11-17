// Builds the app and extension icons: God's hand from Michelangelo's *Creation of Adam*, reaching
// left with the spark of life at his fingertip, in pixel art against a night sky. The scene is a
// 32×32 grid drawn as hard-edged blocks (to match the pixel-art patrons), rendered at 1024 px and
// scaled down for the smaller sizes. Writes an .iconset and converts it with iconutil, and with a
// second argument also writes the extension's icon-{16,32,48,128}.png there.
//
// usage: swift tools/make-icon.swift <out.icns> [extension-icons-dir]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard (2...3).contains(CommandLine.arguments.count) else {
    print("usage: make-icon.swift <out.icns> [extension-icons-dir]"); exit(1)
}

typealias RGB = (r: Int, g: Int, b: Int)
let skyTop: RGB = (22, 34, 72), skyBottom: RGB = (58, 88, 140)
let star: RGB = (200, 214, 240)
let gold: RGB = (232, 193, 90), spark: RGB = (255, 248, 220)
let outline: RGB = (70, 40, 34)
let skin: RGB = (240, 196, 150), skinShade: RGB = (204, 148, 108)
let robe: RGB = (198, 136, 168), robeShade: RGB = (150, 94, 130)
let hills: RGB = (20, 32, 62)  // the squircle's base colour, under its drop shadow

let grid = 32

// The hand, from row 9 down. O outline, S/s skin lit/shaded, R/r robe lit/shaded, . sky.
let handTop = 9
let hand: [String] = [
    ".........................OOOOOOO",
    "........................ORRRRRRR",
    "..................OOOOOOORRRRRRR",
    "................OOSSSSSSORRRRRRR",
    "......OOOOOOOOOOSSSSSSSSORRRRRRR",
    ".....OSSSSSSSSSSSSSSSSSSORRRRRRR",
    ".....OssssssssssSSSSSSSSORRRRRRR",
    "......OOOOOOOOOOSSSSSSSSORRRRRRR",
    "...........OSSSSSSSSSSSSOrRRRRRR",
    "...........OssSSSSSSSSSsOrrRRRRR",
    "............OOOSSSSSSSsOOOOrrRRR",
    "...............OSSSSSsO....OOrrR",
    "...............OssSSsO......OOrr",
    "................OOOSsO.......OOO",
    "...................OO...........",
]
let palette: [Character: RGB] = ["O": outline, "S": skin, "s": skinShade, "R": robe, "r": robeShade]

/// Colour of grid cell (x, y), y growing downward.
func cell(_ x: Int, _ y: Int) -> RGB {
    let row = y - handTop
    if hand.indices.contains(row), let c = palette[Array(hand[row])[x]] { return c }

    // The spark of life, in the gap before his fingertip.
    if (x, y) == (2, 14) { return spark }
    if [(2, 13), (1, 14), (3, 14), (2, 15)].contains(where: { $0 == (x, y) }) { return gold }
    if [(4, 11), (0, 12)].contains(where: { $0 == (x, y) }) { return spark }

    // A few stars, then the sky gradient in coarse bands.
    if [(4, 3), (26, 5), (9, 7), (20, 3), (14, 2), (2, 27), (24, 28), (11, 29), (29, 25)].contains(where: { $0 == (x, y) }) { return star }
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
func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
if CommandLine.arguments.count == 3 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[2])
    for size in [16, 32, 48, 128] { writePNG(render(size: size), dir.appendingPathComponent("icon-\(size).png")) }
    print("wrote extension icons to \(dir.path)")
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
try? FileManager.default.removeItem(at: iconset)
print("wrote \(out.path)")

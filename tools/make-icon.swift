// Builds the extension icons from Art/icon-source.png: a square image with the artwork in
// a rounded square on a dark background (as image generators tend to give it). The rounded square
// is found automatically, cut out a few pixels inside its edge (so none of the dark background
// fringes it), and placed on the macOS icon grid with a soft shadow, at 1024 px and scaled down
// for the smaller sizes. Writes icon-{16,32,48,128}.png into the given folder.
//
// usage: swift tools/make-icon.swift <extension-icons-dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    print("usage: make-icon.swift <extension-icons-dir>"); exit(1)
}

let sourceURL = URL(fileURLWithPath: "Art/icon-source.png")
guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    print("can't read \(sourceURL.path)"); exit(1)
}

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// The artwork's rounded square in `image` (top-left origin), and its corner radius.
func findArtwork(_ image: CGImage) -> (rect: CGRect, radius: Double) {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
    func lit(_ x: Int, _ y: Int) -> Bool {
        let i = (y * w + x) * 4
        return Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) > 150
    }
    let minX = (0..<w).first { lit($0, h / 2) }!, maxX = (0..<w).last { lit($0, h / 2) }!
    let minY = (0..<h).first { lit(w / 2, $0) }!, maxY = (0..<h).last { lit(w / 2, $0) }!
    // How far the corner cuts in along the diagonal gives the radius of a circular corner.
    var gap = 0
    while !lit(minX + gap, minY + gap) { gap += 1 }
    return (CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), Double(gap) / (1 - 1 / 2.0.squareRoot()))
}

func renderMaster() -> CGImage {
    let s = 1024.0
    let ctx = context(1024)
    ctx.interpolationQuality = .high
    let art = findArtwork(source)
    let trim = 0.012 * art.rect.width  // inside the edge, clear of any dark fringe
    let crop = source.cropping(to: art.rect.insetBy(dx: trim, dy: trim))!

    // A 824/1024 body, centered (the macOS icon grid); the corners keep the artwork's own rounding.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = (art.radius - trim) * body.width / (art.rect.width - 2 * trim)
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(crop, in: body)
    ctx.restoreGState()
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

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 48, 128] { writePNG(render(size: size), dir.appendingPathComponent("icon-\(size).png")) }
print("wrote extension icons to \(dir.path)")

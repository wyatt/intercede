// Repacks an irregular AI/hand-drawn sprite sheet into a uniform grid the app can slice.
// Each frame is located inside its nominal source cell via alpha, faint matte noise is
// dropped, and every frame is bottom-aligned to a shared baseline so switching
// animations doesn't make the character hop.
//
// usage: swift tools/pack-sprite.swift <in.png> <out.png> <frames-per-row,...> [cellW cellH]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: pack-sprite.swift <in.png> <out.png> <frames-per-row,...> [cellW cellH]")
    exit(1)
}
let frameCounts = args[3].split(separator: ",").map { Int($0)! }
let outW = args.count > 5 ? Int(args[4])! : 176
let outH = args.count > 5 ? Int(args[5])! : 200
let baselinePad = 4
let noiseAlpha: UInt8 = 32  // matte fringe below this is discarded
let edgeAlpha: UInt8 = 64   // threshold used to measure a frame's bounding box

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot read \(args[1])"); exit(1)
}
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue
CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)!
    .draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

let cols = frameCounts.max()!
let rows = frameCounts.count
let cellW = Double(w) / Double(cols)
let cellH = Double(h) / Double(rows)

var out = [UInt8](repeating: 0, count: outW * cols * outH * rows * 4)
let outStride = outW * cols * 4

for (r, count) in frameCounts.enumerated() {
    for c in 0..<count {
        let x0 = Int((Double(c) * cellW).rounded()), x1 = min(Int((Double(c + 1) * cellW).rounded()), w)
        let y0 = Int((Double(r) * cellH).rounded()), y1 = min(Int((Double(r + 1) * cellH).rounded()), h)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in y0..<y1 { for x in x0..<x1 where px[(y * w + x) * 4 + 3] >= edgeAlpha {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { print("row \(r + 1) frame \(c + 1): empty"); exit(1) }
        let fw = maxX - minX + 1, fh = maxY - minY + 1
        guard fw <= outW, fh <= outH - baselinePad else {
            print("row \(r + 1) frame \(c + 1): \(fw)x\(fh) exceeds cell"); exit(1)
        }
        // Keep the frame's horizontal position within its source cell (preserves walk-cycle
        // sway and gesture reach), clamped so it fits; snap its bottom to the baseline.
        let dx = c * outW + min(max(minX - x0 + (outW - (x1 - x0)) / 2, 0), outW - fw) - minX
        let dy = r * outH + (outH - baselinePad - 1) - maxY
        for y in minY...maxY { for x in minX...maxX {
            let s = (y * w + x) * 4
            guard px[s + 3] >= noiseAlpha else { continue }
            let d = (y + dy) * outStride + (x + dx) * 4
            for k in 0..<4 { out[d + k] = px[s + k] }
        } }
        print("row \(r + 1) frame \(c + 1): \(fw)x\(fh)")
    }
}

let outCtx = CGContext(data: &out, width: outW * cols, height: outH * rows, bitsPerComponent: 8,
                       bytesPerRow: outStride, space: space, bitmapInfo: info)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, outCtx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { print("write failed"); exit(1) }
print("wrote \(args[2]) — \(cols)x\(rows) grid of \(outW)x\(outH) cells")

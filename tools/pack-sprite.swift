// Repacks an irregular AI/hand-drawn sprite sheet into a uniform grid the app can slice.
// Each frame is located inside its nominal source cell via alpha, faint matte noise is
// dropped, and every frame is bottom-aligned to a shared baseline so switching
// animations doesn't make the character hop. Sheets drawn on an opaque light background have it
// flood-filled away from the cell borders first (so a white beard inside an outline survives).
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
let outH = args.count > 5 ? Int(args[5])! : 208
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

// Opaque background (essentially no transparent pixels): remove it by flood fill. Starting from the
// image edge and the nominal cell borders, clear every connected pixel that is light and unsaturated.
let transparentCount = stride(from: 3, to: px.count, by: 4).reduce(0) { $0 + (px[$1] < 16 ? 1 : 0) }
if transparentCount * 20 < w * h {
    func isBackground(_ i: Int) -> Bool {
        let a = Int(px[i + 3])
        if a < 32 { return true }
        // Unpremultiply to judge the colour itself.
        let r = Int(px[i]) * 255 / a, g = Int(px[i + 1]) * 255 / a, b = Int(px[i + 2]) * 255 / a
        return min(r, g, b) >= 200 && max(r, g, b) - min(r, g, b) <= 30
    }
    var seen = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    func seed(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let p = y * w + x
        if !seen[p] && isBackground(p * 4) { seen[p] = true; stack.append(p) }
    }
    let gridCols = frameCounts.max()!, gridRows = frameCounts.count
    for x in 0..<w { seed(x, 0); seed(x, h - 1) }
    for y in 0..<h { seed(0, y); seed(w - 1, y) }
    for c in 1..<gridCols { let x = Int(Double(c) * Double(w) / Double(gridCols)); for y in 0..<h { seed(x, y) } }
    for r in 1..<gridRows { let y = Int(Double(r) * Double(h) / Double(gridRows)); for x in 0..<w { seed(x, y) } }
    var cleared = 0
    while let p = stack.popLast() {
        for k in 0..<4 { px[p * 4 + k] = 0 }
        cleared += 1
        let x = p % w, y = p / w
        seed(x + 1, y); seed(x - 1, y); seed(x, y + 1); seed(x, y - 1)
    }
    print("opaque background removed: \(cleared * 100 / (w * h))% of pixels")
}

let cols = frameCounts.max()!
let rows = frameCounts.count
let cellW = Double(w) / Double(cols)
let cellH = Double(h) / Double(rows)

// Row boundaries: artists (and image generators) rarely space rows evenly, so cut each boundary
// through the widest empty horizontal gap near where it nominally falls. Without a gap, use the even split.
func rowIsEmpty(_ y: Int) -> Bool {
    var x = 0
    while x < w { if px[(y * w + x) * 4 + 3] >= edgeAlpha { return false }; x += 1 }
    return true
}
var rowEdges = [0]
for r in 1..<rows {
    let nominal = Int((Double(r) * cellH).rounded())
    let window = Int(cellH * 0.3)
    var best: (start: Int, length: Int)? = nil
    var y = max(nominal - window, 1)
    while y < min(nominal + window, h - 1) {
        guard rowIsEmpty(y) else { y += 1; continue }
        var end = y
        while end + 1 < h && rowIsEmpty(end + 1) { end += 1 }
        let length = end - y + 1
        if best == nil || length > best!.length { best = (y, length) }
        y = end + 1
    }
    rowEdges.append(best.map { $0.start + $0.length / 2 } ?? nominal)
}
rowEdges.append(h)

var out = [UInt8](repeating: 0, count: outW * cols * outH * rows * 4)
let outStride = outW * cols * 4

// Pieces of neighbouring frames (sparkles spilling across the line, a halo poking up from the row
// below) are excluded from this frame's bounds and not copied into it. A piece is a neighbour's if
// it touches a side border, touches the bottom border below the figure's feet, or is a small speck
// wholly beside the figure and nearer the border than the figure. Nothing touching the top border is
// removed, since that's where this frame's own halo can sit.
func strayEdgeSpecks(x0: Int, x1: Int, y0: Int, y1: Int) -> Set<Int> {
    let maxSpeck = 300          // px, for specks beside the figure (sparkles)
    let maxBorderFragment = 1500  // px, for pieces touching the border (e.g. a neighbour's halo); a figure is many thousands
    let edgeMargin = 4  // px from the border that still counts as touching it
    struct Component {
        var pixels: [Int]; var minX: Int; var maxX: Int; var minY: Int; var maxY: Int
        var touchesSide = false, touchesBottom = false
    }
    var visited = Set<Int>(), components: [Component] = []
    for y in y0..<y1 { for x in x0..<x1 {
        let start = y * w + x
        guard px[start * 4 + 3] >= noiseAlpha, !visited.contains(start) else { continue }
        var comp = Component(pixels: [start], minX: x, maxX: x, minY: y, maxY: y)
        var stack = [start]
        visited.insert(start)
        while let p = stack.popLast() {
            let cx = p % w, cy = p / w
            comp.minX = min(comp.minX, cx); comp.maxX = max(comp.maxX, cx)
            comp.minY = min(comp.minY, cy); comp.maxY = max(comp.maxY, cy)
            if cx < x0 + edgeMargin || cx >= x1 - edgeMargin { comp.touchesSide = true }
            if cy >= y1 - edgeMargin { comp.touchesBottom = true }
            for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
            where nx >= x0 && nx < x1 && ny >= y0 && ny < y1 {
                let n = ny * w + nx
                if px[n * 4 + 3] >= noiseAlpha && !visited.contains(n) {
                    visited.insert(n); stack.append(n); comp.pixels.append(n)
                }
            }
        }
        components.append(comp)
    } }
    guard let main = components.max(by: { $0.pixels.count < $1.pixels.count }) else { return [] }
    var stray = Set<Int>()
    for comp in components where comp.pixels.count <= maxBorderFragment && comp.pixels.count != main.pixels.count {
        // Side border: spill from the frame beside. Bottom border and wholly below the feet: the next
        // row's halo. The top border is left alone — that's where this frame's own halo lives.
        var isStray = comp.touchesSide || (comp.touchesBottom && comp.minY > main.maxY)
        if comp.pixels.count <= maxSpeck {
            if comp.maxX < main.minX {         // wholly left of the figure
                isStray = isStray || (comp.minX - x0) < (main.minX - comp.maxX)
            } else if comp.minX > main.maxX {  // wholly right of the figure
                isStray = isStray || (x1 - 1 - comp.maxX) < (comp.minX - main.maxX)
            }
        }
        if isStray { stray.formUnion(comp.pixels) }
    }
    return stray
}

for (r, count) in frameCounts.enumerated() {
    for c in 0..<count {
        let x0 = Int((Double(c) * cellW).rounded()), x1 = min(Int((Double(c + 1) * cellW).rounded()), w)
        let y0 = rowEdges[r], y1 = rowEdges[r + 1]
        let stray = strayEdgeSpecks(x0: x0, x1: x1, y0: y0, y1: y1)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in y0..<y1 { for x in x0..<x1 where px[(y * w + x) * 4 + 3] >= edgeAlpha && !stray.contains(y * w + x) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { print("row \(r + 1) frame \(c + 1): empty"); exit(1) }
        let fw = maxX - minX + 1, fh = maxY - minY + 1
        guard fw <= outW, fh <= outH - baselinePad else {
            print("row \(r + 1) frame \(c + 1): \(fw)x\(fh) at x \(minX)-\(maxX), y \(minY)-\(maxY) (cell x \(x0)-\(x1 - 1)) exceeds \(outW)x\(outH - baselinePad)"); exit(1)
        }
        // Keep the frame's horizontal position within its source cell (preserves walk-cycle
        // sway and gesture reach), clamped so it fits; snap its bottom to the baseline.
        let dx = c * outW + min(max(minX - x0 + (outW - (x1 - x0)) / 2, 0), outW - fw) - minX
        let dy = r * outH + (outH - baselinePad - 1) - maxY
        for y in minY...maxY { for x in minX...maxX {
            let s = (y * w + x) * 4
            guard px[s + 3] >= noiseAlpha, !stray.contains(y * w + x) else { continue }
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

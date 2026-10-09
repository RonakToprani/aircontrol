// AirControl app icon — cleanup + size ladder for the photoreal wireframe
// constellation hand (app/Tools/AppIcon-source.png, 1024×1024).
//
//   swift app/Tools/PrepareIcon.swift <source.png> <out-dir>
//
// 1. Removes the stray bronze rim/inner lines the image model drew around
//    the tile (everything bronze-tinted OUTSIDE the hand's box is inpainted
//    from the tile colour just inside it).
// 2. Builds every size of the .icns ladder with Lanczos downscaling, then a
//    size-tuned unsharp mask + contrast lift so the thin struts survive the
//    Dock's 16–64px sizes instead of dissolving into grey mush.
// Writes AppIcon.iconset/*.png + AppIcon.icns into <out-dir>.

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let args = CommandLine.arguments
guard args.count > 2, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: PrepareIcon.swift <source.png> <out-dir>"); exit(1)
}
let out = args[2]
let W = cg.width, H = cg.height

// MARK: 1. artifact cleanup on raw RGBA bytes

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bpr = W * 4
// A raw buffer, not a Swift Array: the context must see our writes, and an
// Array copied for `orig` would silently copy-on-write px away from it.
let px = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * H)
px.initialize(repeating: 0, count: bpr * H)
let ctx = CGContext(data: px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: bpr, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

// The hand occupies roughly the middle of the tile; the rim/inner lines are
// all outside this box. Context rows are bottom-up, so flip y for the box.
let handBox = CGRect(x: 0.20 * CGFloat(W), y: 0.05 * CGFloat(H), width: 0.60 * CGFloat(W), height: 0.86 * CGFloat(H))
let cx = W / 2, cy = H / 2
@inline(__always) func at(_ x: Int, _ y: Int) -> Int { y * bpr + x * 4 }
@inline(__always) func lum(_ i: Int) -> Int { (Int(px[i]) * 3 + Int(px[i + 1]) * 6 + Int(px[i + 2])) / 10 }
// A line pixel is one that is clearly brighter than the tile a little
// further INWARD (toward the tile centre, along whichever axis the pixel is
// further out on — so horizontal rim segments walk vertically, and vice
// versa). The tile itself is a smooth dark gradient, so a 22-level jump
// over 12px is never natural tile.
let inset = 12, jump = 11, dilate = 2
var fixed = 0
let orig = Array(UnsafeBufferPointer(start: px, count: bpr * H)) // untouched copy for detection
func lumO(_ i: Int) -> Int { (Int(orig[i]) * 3 + Int(orig[i + 1]) * 6 + Int(orig[i + 2])) / 10 }
func inward(_ x: Int, _ y: Int, _ k: Int) -> Int {
    let dx = x < cx ? 1 : -1, dy = y < cy ? 1 : -1
    return abs(x - cx) > abs(y - cy) ? at(x + dx * k, y) : at(x, y + dy * k)
}
// Pass 1: mark line pixels (clearly brighter than the tile a little inward).
var mask = [Bool](repeating: false, count: W * H)
for y in 0..<H {
    for x in 0..<W {
        let i = at(x, y)
        if orig[i + 3] < 200 || handBox.contains(CGPoint(x: x, y: H - 1 - y)) { continue }
        var s = inward(x, y, inset)
        if lumO(s) - lumO(inward(x, y, inset * 2)) > jump { s = inward(x, y, inset * 2) }
        if lumO(i) - lumO(s) > jump { mask[y * W + x] = true }
    }
}
// Pass 2: grow the mask so the lines' soft antialiased edges go too, then
// fill every masked pixel from clean tile further inward.
var grown = mask
for y in dilate..<(H - dilate) {
    for x in dilate..<(W - dilate) where mask[y * W + x] {
        for yy in (y - dilate)...(y + dilate) { for xx in (x - dilate)...(x + dilate) { grown[yy * W + xx] = true } }
    }
}
for y in 0..<H {
    for x in 0..<W where grown[y * W + x] {
        let i = at(x, y)
        if orig[i + 3] < 200 || handBox.contains(CGPoint(x: x, y: H - 1 - y)) { continue }
        var k = inset
        var s = inward(x, y, k)
        while k < 60, (grown[s / 4 / W * 0 + ((s / bpr) * W + (s % bpr) / 4)] || orig[s + 3] < 200) { k += 4; s = inward(x, y, k) }
        px[i] = orig[s]; px[i + 1] = orig[s + 1]; px[i + 2] = orig[s + 2]
        fixed += 1
    }
}
let cleaned = ctx.makeImage()!
print("inpainted \(fixed) px")

// MARK: 2. size ladder with per-size sharpening

let ci = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
func scaled(_ img: CIImage, to size: Int) -> CIImage {
    guard size < W else { return img }
    let l = CIFilter.lanczosScaleTransform()
    l.inputImage = img; l.scale = Float(size) / Float(W); l.aspectRatio = 1
    return l.outputImage!
}

func render(_ size: Int) -> Data {
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    let src = CIImage(cgImage: cleaned)
    var img = scaled(src, to: size)
    // Small sizes: the struts are 1-2px of mid-grey on near-black at 1024 —
    // a straight downscale averages them into the tile and the hand
    // vanishes. Fix it WITHOUT touching the tile: isolate the bright detail
    // (crush the tile to black), thicken it, downscale that layer on its
    // own, brighten it, and add it back over the normally-scaled icon.
    let dilate: Float = size <= 16 ? 2.4 : size <= 32 ? 2.0 : size <= 64 ? 1.2 : size <= 128 ? 0.6 : 0
    let gain: Float   = size <= 16 ? 0.8 : size <= 32 ? 0.95 : size <= 64 ? 0.8 : size <= 128 ? 0.35 : 0
    if dilate > 0 {
        let crush = CIFilter.toneCurve()
        crush.inputImage = src
        crush.point0 = CGPoint(x: 0, y: 0); crush.point1 = CGPoint(x: 0.24, y: 0)
        crush.point2 = CGPoint(x: 0.45, y: 0.40); crush.point3 = CGPoint(x: 0.7, y: 0.7); crush.point4 = CGPoint(x: 1, y: 1)
        let mx = CIFilter.morphologyMaximum()
        mx.inputImage = crush.outputImage!; mx.radius = dilate
        var struts = scaled(mx.outputImage!.cropped(to: full), to: size)
        let ex = CIFilter.exposureAdjust()
        ex.inputImage = struts; ex.ev = gain
        struts = ex.outputImage!
        let add = CIFilter.additionCompositing()
        add.inputImage = struts; add.backgroundImage = img
        img = add.outputImage!
    }
    let cc = CIFilter.colorControls()
    cc.inputImage = img
    cc.contrast = size <= 64 ? 1.06 : 1.0
    cc.saturation = 1.0
    img = cc.outputImage!
    let us = CIFilter.unsharpMask()
    us.inputImage = img
    us.radius = size <= 32 ? 0.8 : size <= 64 ? 1.0 : 1.5
    us.intensity = size <= 32 ? 0.9 : size <= 64 ? 0.7 : size <= 128 ? 0.5 : 0.2
    img = us.outputImage!
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let outCG = ci.createCGImage(img.cropped(to: rect), from: rect, format: .RGBA8, colorSpace: space)!
    let rep = NSBitmapImageRep(cgImage: outCG)
    return rep.representation(using: .png, properties: [:])!
}

let set = "\(out)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", set, "-o", "\(out)/AppIcon.icns"]
task.launch(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(out)/AppIcon.icns" : "iconutil failed")
exit(task.terminationStatus)

// Builds the macOS app icon from the iOS artwork (Tools/icon/source-1024.png).
//
// The iOS icon is full-bleed; iOS applies the mask. macOS expects the shape in the artwork
// itself: an 824 pt continuous-corner squircle centred on a 1024 canvas, with its own shadow.
// Usage: swift Tools/make_icon.swift   (from the repo root)
import AppKit

let source = NSImage(contentsOfFile: "Tools/icon/source-1024.png")!
let out = "MacRadio/Assets.xcassets/AppIcon.appiconset"

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    // Drop shadow under the tile, as system icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    NSGraphicsContext.current!.imageInterpolation = .high
    source.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(points * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(out)/Contents.json"))
print("OK")

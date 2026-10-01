// Draws the app icon (a sunset gradient with film grain and a vignette, made with the app's own engine)
// and writes AppIcon.icns next to this file.   Run: ./make_icon.sh
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let here = URL(fileURLWithPath: CommandLine.arguments[1])      // folder to write into
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let art = 824                                                  // macOS icon grid: art is 824 of 1024

// 1. the picture: dusk blue at the top, orange at the horizon
var bytes = [UInt8](repeating: 0, count: art * art * 4)
bytes.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: art, height: art, bitsPerComponent: 8, bytesPerRow: art * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let colors = [CGColor(red: 0.13, green: 0.16, blue: 0.36, alpha: 1), CGColor(red: 0.55, green: 0.32, blue: 0.52, alpha: 1),
                  CGColor(red: 0.98, green: 0.55, blue: 0.28, alpha: 1), CGColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 0.8, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(art)), end: CGPoint(x: 0, y: 0), options: [])
}

// 2. the effect itself
let settings = GrainSettings(intensity: 0.38, scale: 10, temperature: 0, vignette: 0.55, seed: 7)
let source = Pixels(width: art, height: art, data: bytes)
let noise = GrainEngine.noise(width: art, height: art, scale: settings.scale, seed: settings.seed)
let grained = GrainEngine.render(source, noise: noise, settings: settings)
let picture = ImageFiles.makeCGImage(grained, colorSpace: space)!

// 3. place it on the 1024 canvas with rounded corners and a soft shadow
func icon(size: Int) -> CGImage {
    let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    canvas.interpolationQuality = .high
    let k = CGFloat(size) / 1024
    let rect = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    canvas.saveGState()
    canvas.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.35))
    canvas.addPath(shape); canvas.setFillColor(CGColor(gray: 0, alpha: 1)); canvas.fillPath()
    canvas.restoreGState()
    canvas.saveGState()
    canvas.addPath(shape); canvas.clip()
    canvas.draw(picture, in: rect)
    canvas.restoreGState()
    return canvas.makeImage()!
}

let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let url = iconset.appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, icon(size: px), nil)
    CGImageDestinationFinalize(dest)
}
print("iconset written")

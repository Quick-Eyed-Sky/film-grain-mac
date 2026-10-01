// Film Grain -- reading and writing picture files.
//
// Derived from the ComfyUI "FilmGrain" node (GPL-3.0), see GrainEngine.swift.
//
// The aim is that nothing is lost on the way: the colour profile is kept, and so
// are the EXIF and XMP blocks (Draw Things stores its generation settings there).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var type: UTType { self == .png ? .png : .jpeg }
}

struct SourceImage {
    let url: URL
    let pixels: Pixels
    let colorSpace: CGColorSpace
    let metadata: CGImageMetadata?
    let hadTransparency: Bool
    var name: String { url.lastPathComponent }
}

enum ImageFileError: LocalizedError {
    case unreadable(String)
    case cannotWrite(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Can't read \"\(name)\" as a picture."
        case .cannotWrite(let name): return "Can't write \"\(name)\"."
        }
    }
}

enum ImageFiles {

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    // MARK: - Reading

    static func load(_ url: URL) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              var cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageFileError.unreadable(url.lastPathComponent) }

        // Phone photos carry an "orientation" tag: turn the pixels upright now, so the
        // saved copy is upright too (the tag is removed again when saving).
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation != 1 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(cgImage.width, cgImage.height),
            ]
            if let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                cgImage = upright
            }
        }

        // Work in the picture's own colour space so its colours are not converted.
        var space = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if space.model != .rgb { space = CGColorSpace(name: CGColorSpace.sRGB)! }

        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let hasAlpha: Bool
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if hasAlpha {   // transparency is flattened onto white
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(rect)
            }
            context.draw(cgImage, in: rect)
            return true
        }
        guard drawn else { throw ImageFileError.unreadable(url.lastPathComponent) }

        return SourceImage(
            url: url,
            pixels: Pixels(width: width, height: height, data: data),
            colorSpace: space,
            metadata: CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            hadTransparency: hasAlpha
        )
    }

    /// A picture the screen can show, from raw pixels.
    static func makeCGImage(_ pixels: Pixels, colorSpace: CGColorSpace) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels.data) as CFData) else { return nil }
        return CGImage(
            width: pixels.width, height: pixels.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    // MARK: - Writing

    static func save(_ result: Pixels, from source: SourceImage, format: OutputFormat, to url: URL) throws {
        guard let image = makeCGImage(result, colorSpace: source.colorSpace),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw ImageFileError.cannotWrite(url.lastPathComponent) }

        var options: [CFString: Any] = [:]
        if format == .jpeg { options[kCGImageDestinationLossyCompressionQuality] = 0.95 }

        if let original = source.metadata, let metadata = CGImageMetadataCreateMutableCopy(original) {
            CGImageMetadataRemoveTagWithPath(metadata, nil, "tiff:Orientation" as CFString)   // pixels are upright already
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, options as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageFileError.cannotWrite(url.lastPathComponent) }
    }

    /// `name_grain.png`, or `name_grain_2.png`, `_3`... if that name is already taken.
    /// The original is never overwritten: its name never ends in `_grain`.
    static func freeURL(beside original: URL, format: OutputFormat) -> URL {
        let folder = original.deletingLastPathComponent()
        let stem = original.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(stem)_grain.\(format.fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path)
            || FileManager.default.fileExists(atPath: candidate.deletingPathExtension().appendingPathExtension("txt").path) {
            candidate = folder.appendingPathComponent("\(stem)_grain_\(n).\(format.fileExtension)")
            n += 1
        }
        return candidate
    }

    /// The settings of one result, written to a .txt next to it, so nothing is irreproducible.
    static func writeSettingsFile(for resultURL: URL, source: SourceImage, settings: GrainSettings, format: OutputFormat) {
        let textURL = resultURL.deletingPathExtension().appendingPathExtension("txt")
        let when = ISO8601DateFormatter().string(from: Date())
        var text = """
        \(AppInfo.name) \(AppInfo.version)
        Date:          \(when)
        Original:      \(source.name)
        Result:        \(resultURL.lastPathComponent)
        Size:          \(source.pixels.width) x \(source.pixels.height) px
        Format:        \(format.rawValue)

        Strength:      \(String(format: "%.2f", settings.intensity))
        Scale:         \(String(format: "%.0f", settings.scale))
        Warmth:        \(String(format: "%.0f", settings.temperature))
        Vignette:      \(String(format: "%.2f", settings.vignette))
        Seed:          \(settings.seed)
        """
        if source.hadTransparency { text += "\n\nNote: the original had transparency; it was flattened onto white." }
        text += "\n\nSame original + same settings + same seed = same pixels.\n"
        try? text.write(to: textURL, atomically: true, encoding: .utf8)
    }
}

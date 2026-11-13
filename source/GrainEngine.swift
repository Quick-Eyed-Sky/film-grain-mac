// Film Grain -- the pixel maths, with no user interface in it.
//
// This is a Swift re-implementation of the "FilmGrain" node from
// ComfyUI-post-processing-nodes by EllangoK
//   https://github.com/EllangoK/ComfyUI-post-processing-nodes
//   (post_processing/film_grain.py)
// which is released under the GNU General Public License v3.0.
// This program is a derived work and is therefore under the same licence
// (see the LICENSE file next to the app).
//
// What differs from the node, on purpose:
//   * the random numbers come from a seed, so the same seed and settings always
//     give the same pixels (the node uses an unseeded random generator);
//   * the grain pattern is cached: moving Strength / Warmth / Vignette does not
//     recompute it, only Scale and Seed do.

import Foundation

enum AppInfo {
    static let name = "Film Grain"
    // Single source of truth: the window header, the Info.plist and the
    // .txt files written next to each result all read this line.
    static let version = "0.6.1"
}

/// Everything the user can change. The defaults are the ones of the ComfyUI node.
struct GrainSettings: Equatable, Codable {
    var intensity: Double = 0.2      // 0 ... 1
    var scale: Double = 10           // 1 ... 100
    var temperature: Double = 0      // -100 ... 100
    var vignette: Double = 0         // 0 ... 1
    var seed: Int = 1234
    var saturation: Double = 1       // 0 ... 2; 1 leaves colours unchanged

    var grainSize: Double = 1       // 1 ... 6 pixels
    var brightness: Double = 0       // -1 ... 1
    var contrast: Double = 0         // -1 ... 1
    var shadows: Double = 0          // -1 ... 1
    var highlights: Double = 0        // -1 ... 1
    var vignetteFeather: Double = 0.5 // 0 ... 1; 0.5 preserves the original vignette
    var halation: Double = 0         // 0 ... 1

    init() {}

    // Settings saved by version 0.4 have no saturation field.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try values.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.2
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? 10
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        vignette = try values.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        seed = try values.decodeIfPresent(Int.self, forKey: .seed) ?? 1234
        saturation = try values.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        grainSize = try values.decodeIfPresent(Double.self, forKey: .grainSize) ?? 1
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try values.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        shadows = try values.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        highlights = try values.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        vignetteFeather = try values.decodeIfPresent(Double.self, forKey: .vignetteFeather) ?? 0.5
        halation = try values.decodeIfPresent(Double.self, forKey: .halation) ?? 0
    }
}

/// An 8-bit picture, 4 bytes per pixel in the order R, G, B, unused.
struct Pixels {
    let width: Int
    let height: Int
    var data: [UInt8]
}

enum GrainEngine {

    // MARK: - Grain pattern

    /// Multi-octave gradient noise with one random gradient per pixel, as in the
    /// node, scaled so that its smallest value is -1 and its largest is +1.
    static func noise(width: Int, height: Int, scale: Double, seed: Int) -> [Float] {
        let octaves = 4
        let persistence: Float = 0.5

        // For each octave, the position inside its cell and the smoothed position
        // (smoothstep) along each axis. Both axes are separable, so these small
        // tables replace the full-size arrays of the original.
        var xFrac = [Float](repeating: 0, count: octaves * width)
        var xFade = xFrac
        var yFrac = [Float](repeating: 0, count: octaves * height)
        var yFade = yFrac
        for o in 0..<octaves {
            let cells = scale * pow(2.0, Double(o))
            fillAxis(count: width, cells: cells, frac: &xFrac, fade: &xFade, offset: o * width)
            fillAxis(count: height, cells: cells, frac: &yFrac, fade: &yFade, offset: o * height)
        }

        let key = mix64(UInt64(bitPattern: Int64(seed)))
        let rowsPerChunk = 8
        let chunks = (height + rowsPerChunk - 1) / rowsPerChunk
        let mins = UnsafeMutablePointer<Float>.allocate(capacity: chunks)
        let maxs = UnsafeMutablePointer<Float>.allocate(capacity: chunks)
        defer { mins.deallocate(); maxs.deallocate() }

        var field = [Float](unsafeUninitializedCapacity: width * height) { buffer, count in
            let out = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                var lo = Float.infinity
                var hi = -Float.infinity
                let firstRow = chunk * rowsPerChunk
                let lastRow = min(height, firstRow + rowsPerChunk)
                for y in firstRow..<lastRow {
                    for x in 0..<width {
                        let index = y * width + x
                        // 64 random bits per pixel: 8 bits for each of the 4 octaves
                        // (a sign for the x and the y part of each of the 4 corners).
                        let bits = mix64(key ^ (UInt64(index) &* 0xD6E8_FEB8_6659_FD93))
                        var total: Float = 0
                        var weight: Float = 1
                        for o in 0..<octaves {
                            let b = Int(truncatingIfNeeded: bits >> UInt64(8 * o)) & 0xFF
                            let xf = xFrac[o * width + x], u = xFade[o * width + x]
                            let yf = yFrac[o * height + y], v = yFade[o * height + y]
                            let n00 = sign(b, 0) * xf + sign(b, 1) * yf
                            let n10 = sign(b, 2) * (xf - 1) + sign(b, 3) * yf
                            let n01 = sign(b, 4) * xf + sign(b, 5) * (yf - 1)
                            let n11 = sign(b, 6) * (xf - 1) + sign(b, 7) * (yf - 1)
                            let x1 = n00 + u * (n10 - n00)
                            let x2 = n01 + u * (n11 - n01)
                            total += (x1 + v * (x2 - x1)) * weight
                            weight *= persistence
                        }
                        out[index] = total
                        lo = min(lo, total)
                        hi = max(hi, total)
                    }
                }
                mins[chunk] = lo
                maxs[chunk] = hi
            }
            count = width * height
        }

        var lo = Float.infinity, hi = -Float.infinity
        for c in 0..<chunks { lo = min(lo, mins[c]); hi = max(hi, maxs[c]) }
        let span = hi - lo
        if span > 0 {
            let k = 2 / span
            field.withUnsafeMutableBufferPointer { buffer in
                let p = buffer.baseAddress!
                DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                    let from = chunk * rowsPerChunk * width
                    let to = min(width * height, (chunk + 1) * rowsPerChunk * width)
                    for i in from..<to { p[i] = (p[i] - lo) * k - 1 }
                }
            }
        }
        return field
    }

    // MARK: - Grain, warmth, vignette

    /// Applies grain, warmth, saturation and vignette in that order.
    static func render(_ source: Pixels, noise: [Float], settings s: GrainSettings) -> Pixels {
        let w = source.width, h = source.height
        precondition(noise.count == w * h, "noise size does not match the picture")

        let strength = Float(min(max(s.intensity, 0), 1))
        let t = Float(s.temperature / 100)
        let vignette = Float(min(max(s.vignette, 0), 1))
        let saturation = Float(min(max(s.saturation, 0), 2))
        let brightness = Float(min(max(s.brightness, -1), 1))
        let contrast = Float(min(max(s.contrast, -1), 1))
        let shadows = Float(min(max(s.shadows, -1), 1))
        let highlights = Float(min(max(s.highlights, -1), 1))
        let feather = Float(min(max(s.vignetteFeather, 0), 1))
        let halation = Float(min(max(s.halation, 0), 1))
        let grainSize = max(1, min(6, Int(s.grainSize.rounded())))
        if strength == 0 && t == 0 && vignette == 0 && saturation == 1 && brightness == 0 && contrast == 0 && shadows == 0 && highlights == 0 && halation == 0 { return source }
        let glow = halation > 0 ? highlightGlow(source) : nil

        // Vignette: squared distance from the centre, per axis. As in the node the
        // axes run from -1 to +1 and the radius is divided by its largest value.
        var x2 = [Float](repeating: 0, count: w)
        var y2 = [Float](repeating: 0, count: h)
        for i in 0..<w { let v = w > 1 ? -1 + 2 * Double(i) / Double(w - 1) : 0; x2[i] = Float(v * v) }
        for i in 0..<h { let v = h > 1 ? -1 + 2 * Double(i) / Double(h - 1) : 0; y2[i] = Float(v * v) }
        let longest = ((x2.max() ?? 0) + (y2.max() ?? 0)).squareRoot()
        let invLongest: Float = longest > 0 ? 1 / longest : 0

        var result = source
        let rowsPerChunk = 16
        let chunks = (h + rowsPerChunk - 1) / rowsPerChunk
        result.data.withUnsafeMutableBufferPointer { dstBuffer in
            source.data.withUnsafeBufferPointer { srcBuffer in
                noise.withUnsafeBufferPointer { noiseBuffer in
                    let dst = dstBuffer.baseAddress!, src = srcBuffer.baseAddress!
                    let nz = noiseBuffer.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                        let firstRow = chunk * rowsPerChunk
                        let lastRow = min(h, firstRow + rowsPerChunk)
                        for y in firstRow..<lastRow {
                            let rowY2 = y2[y]
                            for x in 0..<w {
                                let i = y * w + x
                                let p = i * 4
                                // Bilinear sampling of a coarser deterministic noise grid creates larger grains.
                                let n: Float
                                if grainSize == 1 { n = nz[i] * strength }
                                else {
                                    let x0 = (x / grainSize) * grainSize, y0 = (y / grainSize) * grainSize
                                    let x1 = min(x0 + grainSize, w - 1), y1 = min(y0 + grainSize, h - 1)
                                    let fx = Float(x - x0) / Float(grainSize), fy = Float(y - y0) / Float(grainSize)
                                    let top = nz[y0 * w + x0] * (1 - fx) + nz[y0 * w + x1] * fx
                                    let bottom = nz[y1 * w + x0] * (1 - fx) + nz[y1 * w + x1] * fx
                                    n = (top * (1 - fy) + bottom * fy) * strength
                                }
                                var r = Float(src[p]) * (1 / 255) + n
                                var g = Float(src[p + 1]) * (1 / 255) + n
                                var b = Float(src[p + 2]) * (1 / 255) + n
                                r = clamp01(r); g = clamp01(g); b = clamp01(b)

                                if brightness != 0 || contrast != 0 || shadows != 0 || highlights != 0 {
                                    let lum = clamp01(0.2126 * r + 0.7152 * g + 0.0722 * b)
                                    let shadowWeight = (1 - lum) * (1 - lum)
                                    let highlightWeight = lum * lum
                                    let shift = brightness * 0.35 + shadows * 0.35 * shadowWeight + highlights * 0.35 * highlightWeight
                                    let gain: Float = contrast >= 0 ? 1 + contrast * 1.5 : 1 + contrast * 0.8
                                    r = clamp01((r - 0.5) * gain + 0.5 + shift)
                                    g = clamp01((g - 0.5) * gain + 0.5 + shift)
                                    b = clamp01((b - 0.5) * gain + 0.5 + shift)
                                }
                                if let glow {
                                    let amount = glow.value(x: x, y: y, width: w, height: h) * halation * 0.60
                                    r = clamp01(r + amount)
                                    g = clamp01(g + amount * 0.30)
                                    b = clamp01(b + amount * 0.12)
                                }

                                if t > 0 {                      // warmer: more red, a little more green
                                    r = clamp01(r * (1 + t))
                                    g = clamp01(g * (1 + t * 0.4))
                                } else if t < 0 {               // cooler: more blue
                                    b = clamp01(b * (1 - t))
                                }

                                if saturation != 1 {
                                    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                                    r = clamp01(luminance + (r - luminance) * saturation)
                                    g = clamp01(luminance + (g - luminance) * saturation)
                                    b = clamp01(luminance + (b - luminance) * saturation)
                                }

                                if vignette > 0 {
                                    let radius = (x2[x] + rowY2).squareRoot() * invLongest
                                    // The midpoint reproduces the 0.5 vignette exactly.
                                    let profile: Float
                                    if feather < 0.5 {
                                        let u = clamp01((radius - 0.65) / 0.35)
                                        let hard = u * u * (3 - 2 * u)
                                        profile = hard * (1 - 2 * feather) + radius * (2 * feather)
                                    } else {
                                        let soft = radius.squareRoot()
                                        profile = radius * (2 - 2 * feather) + soft * (2 * feather - 1)
                                    }
                                    let k = 1 - profile * vignette
                                    r = clamp01(r * k); g = clamp01(g * k); b = clamp01(b * k)
                                }

                                dst[p] = UInt8(r * 255 + 0.5)
                                dst[p + 1] = UInt8(g * 255 + 0.5)
                                dst[p + 2] = UInt8(b * 255 + 0.5)
                                dst[p + 3] = 255
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    private struct GlowMap {
        let width: Int, height: Int
        let values: [Float]
        func value(x: Int, y: Int, width w: Int, height h: Int) -> Float {
            let gx = (Float(x) + 0.5) * Float(width) / Float(w) - 0.5
            let gy = (Float(y) + 0.5) * Float(height) / Float(h) - 0.5
            let x0 = max(0, min(width - 1, Int(floor(gx))))
            let y0 = max(0, min(height - 1, Int(floor(gy))))
            let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = max(0, min(1, gx - Float(x0))), fy = max(0, min(1, gy - Float(y0)))
            let a = values[y0 * width + x0] * (1 - fx) + values[y0 * width + x1] * fx
            let b = values[y1 * width + x0] * (1 - fx) + values[y1 * width + x1] * fx
            return a * (1 - fy) + b * fy
        }
    }

    // Average highlights into a small map, then blur it. Radius scales with the
    // image, so the preview and export use the same full-resolution calculation.
    private static func highlightGlow(_ source: Pixels) -> GlowMap {
        let w = source.width, h = source.height
        let divisor = max(1, (max(w, h) + 511) / 512)
        let mw = (w + divisor - 1) / divisor, mh = (h + divisor - 1) / divisor
        var map = [Float](repeating: 0, count: mw * mh)
        var counts = [Int](repeating: 0, count: mw * mh)
        for y in 0..<h { for x in 0..<w {
            let p = (y * w + x) * 4, i = (y / divisor) * mw + x / divisor
            let lum = (0.2126 * Float(source.data[p]) + 0.7152 * Float(source.data[p + 1]) + 0.0722 * Float(source.data[p + 2])) / 255
            let v = clamp01((lum - 0.70) / 0.30)
            map[i] += v * v; counts[i] += 1
        } }
        for i in map.indices { map[i] /= Float(counts[i]) }
        let radius = max(1, min(8, Int(Float(max(mw, mh)) * 0.012)))
        var temp = map
        for y in 0..<mh { for x in 0..<mw {
            let lo = max(0, x - radius), hi = min(mw - 1, x + radius)
            var sum: Float = 0
            for xx in lo...hi { sum += map[y * mw + xx] }
            temp[y * mw + x] = sum / Float(hi - lo + 1)
        } }
        var blurred = temp
        for y in 0..<mh { for x in 0..<mw {
            let lo = max(0, y - radius), hi = min(mh - 1, y + radius)
            var sum: Float = 0
            for yy in lo...hi { sum += temp[yy * mw + x] }
            blurred[y * mw + x] = sum / Float(hi - lo + 1)
        } }
        return GlowMap(width: mw, height: mh, values: blurred)
    }

    // MARK: - Small helpers

    @inline(__always) private static func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }

    /// Bit `bit` of `b` chooses the direction: 0 -> +1, 1 -> -1.
    @inline(__always) private static func sign(_ b: Int, _ bit: Int) -> Float {
        (b >> bit) & 1 == 0 ? 1 : -1
    }

    private static func fillAxis(count: Int, cells: Double, frac: inout [Float], fade: inout [Float], offset: Int) {
        for i in 0..<count {
            let position = Double(i) / Double(count) * cells
            let f = position - position.rounded(.down)
            frac[offset + i] = Float(f)
            fade[offset + i] = Float(f * f * (3 - 2 * f))
        }
    }

    /// SplitMix64 finaliser: turns any 64-bit number into well-mixed random bits.
    @inline(__always) private static func mix64(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

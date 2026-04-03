import AppKit
import CoreGraphics
import Foundation
import SwiftUI

extension NSImage {
    func averageColor(completion: @Sendable @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let width = max(1, min(cgImage.width, 40))
            let height = max(1, min(cgImage.height, 40))
            let totalPixels = width * height

            guard totalPixels > 0,
                  let context = CGContext(
                      data: nil,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let data = context.data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
            var totalRed: UInt64 = 0
            var totalGreen: UInt64 = 0
            var totalBlue: UInt64 = 0

            for index in 0..<totalPixels {
                let color = pointer[index]
                totalRed += UInt64(color & 0xFF)
                totalGreen += UInt64((color >> 8) & 0xFF)
                totalBlue += UInt64((color >> 16) & 0xFF)
            }

            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0

            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03

            let finalColor: NSColor
            if isNearBlack {
                finalColor = NSColor(white: minBrightness, alpha: 1.0)
            } else {
                var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0

                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                if brightness < minBrightness {
                    let saturationScale = brightness / minBrightness
                    color = NSColor(
                        hue: hue,
                        saturation: saturation * saturationScale,
                        brightness: minBrightness,
                        alpha: alpha
                    )
                }

                finalColor = color
            }

            DispatchQueue.main.async {
                completion(finalColor)
            }
        }
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else { return self }
        guard let rgbColor = NSColor(self).usingColorSpace(.sRGB) else { return self }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)
        guard perceivedBrightness > 0 else { return self }

        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)

        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }
}

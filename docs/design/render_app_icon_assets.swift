import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "TripMap/Assets.xcassets/AppIcon.appiconset")
let background = CGColor(red: 0x6E / 255.0, green: 0x86 / 255.0, blue: 0xA8 / 255.0, alpha: 1)
let card = CGColor(red: 0xF4 / 255.0, green: 0xF1 / 255.0, blue: 0xE8 / 255.0, alpha: 1)
let thread = CGColor(red: 0xD9 / 255.0, green: 0x2D / 255.0, blue: 0x20 / 255.0, alpha: 1)

struct OpticalSpec {
    let gap: CGFloat
    let thread: CGFloat
    let radius: CGFloat
}

func spec(for size: Int) -> OpticalSpec {
    if size <= 64 { return OpticalSpec(gap: 0.28, thread: 0.28, radius: 0.16) }
    if size <= 128 { return OpticalSpec(gap: 0.21, thread: 0.22, radius: 0.12) }
    return OpticalSpec(gap: 0.15, thread: 0.18, radius: 0.09)
}

func roundedRect(_ context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

func render(size: Int) -> CGImage? {
    let dimension = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    let optical = spec(for: size)
    let cardHeight = max(4, round(dimension * 220 / 1024))
    let cardWidth = max(12, round(cardHeight * 2.6))
    let gap = max(1, round(cardHeight * optical.gap))
    let radius = max(1, round(cardHeight * optical.radius))
    let threadWidth = max(1, round(cardHeight * optical.thread))
    let totalHeight = cardHeight * 3 + gap * 2
    let x = round((dimension - cardWidth) / 2)
    let y = round((dimension - totalHeight) / 2)
    let threadX = round(x + cardWidth * 0.25 - threadWidth / 2)
    let threadExtension = max(1, round(cardHeight * 0.24))

    roundedRect(context, x: threadX, y: y - threadExtension, width: threadWidth, height: totalHeight + threadExtension * 2, radius: threadWidth / 2, color: thread)
    let cardYs = [y, y + cardHeight + gap, y + (cardHeight + gap) * 2]
    for cardY in cardYs {
        roundedRect(context, x: x, y: cardY, width: cardWidth, height: cardHeight, radius: radius, color: card)
    }
    for cardY in [cardYs[0], cardYs[2]] {
        context.setFillColor(thread)
        context.fill(CGRect(x: threadX, y: cardY, width: threadWidth, height: cardHeight))
    }
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "IconRenderer", code: 1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "IconRenderer", code: 2) }
}

try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
for size in [16, 32, 40, 58, 60, 64, 80, 87, 120, 128, 180, 256, 512, 1024] {
    if let image = render(size: size) {
        try writePNG(image, to: outputRoot.appendingPathComponent("icon-\(size).png"))
    }
}

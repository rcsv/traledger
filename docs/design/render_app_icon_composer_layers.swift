import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "TripMap/AppIcon.icon/Assets")
let bg = CGColor(red: 0x6E / 255.0, green: 0x86 / 255.0, blue: 0xA8 / 255.0, alpha: 1)
let ivory = CGColor(red: 0xF4 / 255.0, green: 0xF1 / 255.0, blue: 0xE8 / 255.0, alpha: 1)
let red = CGColor(red: 0xD9 / 255.0, green: 0x2D / 255.0, blue: 0x20 / 255.0, alpha: 1)

func pathRect(_ context: CGContext, _ rect: CGRect, radius: CGFloat, _ color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

func makeContext(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func geometry(_ size: Int) -> (CGRect, [CGRect], CGRect) {
    let s = CGFloat(size)
    let gapRatio: CGFloat = size <= 64 ? 0.28 : (size <= 128 ? 0.21 : 0.15)
    let threadRatio: CGFloat = size <= 64 ? 0.28 : (size <= 128 ? 0.22 : 0.18)
    let h = max(4, round(s * 220 / 1024))
    let w = max(12, round(h * 2.6))
    let gap = max(1, round(h * gapRatio))
    let tw = max(1, round(h * threadRatio))
    let total = h * 3 + gap * 2
    let x = round((s - w) / 2)
    let y = round((s - total) / 2)
    let cards = [y, y + h + gap, y + (h + gap) * 2].map { CGRect(x: x, y: $0, width: w, height: h) }
    let threadX = round(x + w * 0.25 - tw / 2)
    let threadExtension = max(1, round(h * 0.24))
    let thread = CGRect(x: threadX, y: y - threadExtension, width: tw, height: total + threadExtension * 2)
    return (CGRect(x: x, y: y, width: w, height: h), cards, thread)
}

func write(_ image: CGImage, _ url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "IconLayers", code: 1) }
}

func render(_ size: Int, _ layer: String) -> CGImage {
    let context = makeContext(size)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    let (_, cards, thread) = geometry(size)
    if layer == "background" {
        context.setFillColor(bg)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    } else if layer == "thread-back" {
        // Only render the portions that are not covered by cards. The front
        // layer owns the crossings over the top and bottom cards, so this
        // layer remains behind the cards regardless of Icon Composer order.
        let segments = [
            CGRect(x: thread.minX, y: thread.minY, width: thread.width, height: max(0, cards[0].minY - thread.minY)),
            CGRect(x: thread.minX, y: cards[0].maxY, width: thread.width, height: max(0, cards[1].minY - cards[0].maxY)),
            CGRect(x: thread.minX, y: cards[1].maxY, width: thread.width, height: max(0, cards[2].minY - cards[1].maxY)),
            CGRect(x: thread.minX, y: cards[2].maxY, width: thread.width, height: max(0, thread.maxY - cards[2].maxY))
        ]
        context.setFillColor(red)
        for segment in segments where segment.height > 0 { context.fill(segment) }
    } else if layer == "top-card" {
        pathRect(context, cards[0], radius: cards[0].height * (size <= 64 ? 0.16 : (size <= 128 ? 0.12 : 0.09)), ivory)
    } else if layer == "top-thread-front" {
        context.setFillColor(red)
        context.fill(cards[0].intersection(thread))
    } else if layer == "middle-card" {
        pathRect(context, cards[1], radius: cards[1].height * (size <= 64 ? 0.16 : (size <= 128 ? 0.12 : 0.09)), ivory)
    } else if layer == "bottom-card" {
        pathRect(context, cards[2], radius: cards[2].height * (size <= 64 ? 0.16 : (size <= 128 ? 0.12 : 0.09)), ivory)
    } else if layer == "bottom-thread-front" {
        context.setFillColor(red)
        context.fill(cards[2].intersection(thread))
    }
    return context.makeImage()!
}

try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for layer in [
    "thread-back",
    "top-card", "top-thread-front",
    "middle-card",
    "bottom-card", "bottom-thread-front"
] {
    try write(render(1024, layer), root.appendingPathComponent("\(layer).png"))
}

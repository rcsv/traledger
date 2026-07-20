import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum TripImageProcessor {
    static let maximumPixelDimension: CGFloat = 1_600

    static func normalizedJPEGData(from data: Data) -> Data? {
        #if os(macOS)
        guard let source = NSImage(data: data) else { return nil }
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maximumPixelDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        #elseif os(iOS)
        guard let source = UIImage(data: data) else { return nil }
        let target = source.preparingThumbnail(
            of: CGSize(width: maximumPixelDimension, height: maximumPixelDimension)
        ) ?? source
        return target.jpegData(compressionQuality: 0.82)
        #else
        return nil
        #endif
    }
}

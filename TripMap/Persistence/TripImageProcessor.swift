import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TripImageProcessor {
    static let maximumPixelDimension = 1_600
    static let maximumEncodedByteCount = 2 * 1_024 * 1_024

    private static let pixelDimensions = [1_600, 1_280, 1_024, 800, 640, 480]
    private static let compressionQualities = [0.82, 0.72, 0.62, 0.52, 0.42]

    static func normalizedJPEGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        for pixelDimension in pixelDimensions {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil
            }

            for quality in compressionQualities {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    output,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                ) else {
                    return nil
                }
                CGImageDestinationAddImage(
                    destination,
                    image,
                    [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
                )
                guard CGImageDestinationFinalize(destination) else { return nil }
                if output.length <= maximumEncodedByteCount {
                    return output as Data
                }
            }
        }

        return nil
    }
}

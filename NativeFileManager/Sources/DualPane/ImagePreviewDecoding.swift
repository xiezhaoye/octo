import Foundation
import ImageIO

final class ImageDecodeRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum ImagePreviewDecoding {
    static let maxPixelSize = 2048
    private static let queue = DispatchQueue(label: "octo.image-preview", qos: .userInitiated)
    /// Serial, cancellable work avoids accumulating full-size decodes while switching quickly.
    static func decode(_ url: URL, request: ImageDecodeRequest) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !request.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache:false] as CFDictionary) else { continuation.resume(returning:nil); return }
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceThumbnailMaxPixelSize:maxPixelSize, kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary)
                continuation.resume(returning:request.isCancelled ? nil : image)
            }
        }
    }
}

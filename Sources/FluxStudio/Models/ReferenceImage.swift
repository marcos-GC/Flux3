import AppKit
import FluxCore
import UniformTypeIdentifiers

/// Imagen de referencia añadida a la barra de prompt ("Image 1", "Image 2"…).
struct ReferenceImage: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var thumbnail: NSImage?
    var encoded: ImageEncoder.Encoded?
    var error: String?

    var isReady: Bool { encoded != nil }
    var isProcessing: Bool { encoded == nil && error == nil }

    static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

/// Miniaturas en segundo plano, con caché.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func load(_ url: URL, maxPixelSize: Int = 512) async -> NSImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = ImageEncoder.thumbnail(fileURL: url, maxPixelSize: maxPixelSize) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

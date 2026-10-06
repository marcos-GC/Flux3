import Foundation

public enum MediaType {
    /// Extensión de archivo a partir del tipo MIME de la descarga o, si no, de la URL.
    public static func fileExtension(mimeType: String?, url: URL?) -> String {
        let mime = (mimeType ?? "").lowercased()
        if mime.contains("jpeg") || mime.contains("jpg") { return "jpg" }
        if mime.contains("png") { return "png" }
        if mime.contains("webp") { return "webp" }
        if mime.contains("mp4") { return "mp4" }
        if mime.contains("quicktime") { return "mov" }
        let ext = (url?.pathExtension ?? "").lowercased()
        switch ext {
        case "jpeg", "jpg": return "jpg"
        case "png", "webp", "mp4", "mov": return ext
        default: return "jpg"
        }
    }
}

public enum AspectRatio {
    /// "2:3" → 0.666…; "auto" o valores raros → nil.
    public static func value(of text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else {
            return nil
        }
        return w / h
    }
}

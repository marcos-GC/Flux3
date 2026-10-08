import AppKit
import AVFoundation
import FluxCore
import SwiftUI

/// Fotograma clave de Imagen a vídeo.
struct VideoKeyframe: Identifiable {
    let id = UUID()
    let url: URL
    var thumbnail: NSImage?
    var encoded: ImageEncoder.Encoded?
    var error: String?
    var seconds: Double = 0

    var isProcessing: Bool { encoded == nil && error == nil }
}

/// Datos básicos de un vídeo local.
struct VideoInfo {
    let duration: Double
    let size: CGSize
    let bytes: Int

    static func load(_ url: URL) async -> VideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        var size = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let r = CGRect(origin: .zero, size: natural).applying(transform)
            size = CGSize(width: abs(r.width), height: abs(r.height))
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return VideoInfo(duration: duration.seconds, size: size, bytes: bytes)
    }
}

/// Estado de la herramienta Vídeo.
@MainActor
final class VideoModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case t2v, i2v, v2v, edit, upscale
        var id: String { rawValue }

        var title: String {
            switch self {
            case .t2v: return "Texto a vídeo"
            case .i2v: return "Imagen a vídeo"
            case .v2v: return "Continuar vídeo"
            case .edit: return "Editar vídeo"
            case .upscale: return "Escalar vídeo"
            }
        }

        var icon: String {
            switch self {
            case .t2v: return "text.cursor"
            case .i2v: return "photo.on.rectangle"
            case .v2v: return "forward.end"
            case .edit: return "wand.and.stars"
            case .upscale: return "arrow.up.left.and.arrow.down.right"
            }
        }

        /// Modos que trabajan sobre el vídeo seleccionado.
        var needsVideo: Bool { self == .v2v || self == .edit || self == .upscale }
    }

    @Published var mode: Mode = .t2v
    @Published var prompt = ""
    @Published var keyframes: [VideoKeyframe] = []
    @Published var useTimestamps = false
    @Published var aspectRatio = "auto"
    /// nil = Auto.
    @Published var duration: Int?
    @Published var resolution = "hd"
    @Published var generateAudio = true
    @Published var draft = false
    @Published var safety: Int
    @Published var creativity = 0
    @Published var upscaleFactor = 2.0
    @Published var finalResolution = "fhd"
    let runner = ToolRunner()

    init(settings: SettingsStore) {
        safety = SafetyTolerance.clamp(settings.defaultSafety, for: .flux3Video)
    }

    nonisolated static func isVideo(_ url: URL?) -> Bool {
        guard let ext = url?.pathExtension.lowercased() else { return false }
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    // MARK: Fotogramas clave

    func addKeyframes(_ urls: [URL]) {
        for url in urls.filter(ReferenceImage.isSupported) where keyframes.count < Flux3Video.maxKeyframes {
            var frame = VideoKeyframe(url: url)
            frame.seconds = keyframes.isEmpty ? 0 : min(20, (keyframes.last?.seconds ?? 0) + 3)
            keyframes.append(frame)
            let id = frame.id
            Task {
                let thumb = await ThumbnailLoader.load(url, maxPixelSize: 200)
                let result = await Task.detached(priority: .userInitiated) { () -> Result<ImageEncoder.Encoded, Error> in
                    Result { try ImageEncoder.encode(fileURL: url) }
                }.value
                guard let i = keyframes.firstIndex(where: { $0.id == id }) else { return }
                keyframes[i].thumbnail = thumb
                switch result {
                case .success(let encoded):
                    if min(encoded.pixelWidth, encoded.pixelHeight) < Flux3Video.minKeyframeSide {
                        keyframes[i].error = "Debe medir al menos \(Flux3Video.minKeyframeSide)×\(Flux3Video.minKeyframeSide) px."
                    } else {
                        keyframes[i].encoded = encoded
                    }
                case .failure(let error):
                    keyframes[i].error = error.localizedDescription
                }
            }
        }
    }

    func removeKeyframe(_ id: UUID) {
        keyframes.removeAll { $0.id == id }
    }

    func moveKeyframe(_ id: UUID, by offset: Int) {
        guard let i = keyframes.firstIndex(where: { $0.id == id }), keyframes.indices.contains(i + offset) else { return }
        keyframes.swapAt(i, i + offset)
    }

    // MARK: Generar

    func generate(state: AppState, focused: URL?) {
        let mode = self.mode
        if mode.needsVideo && !Self.isVideo(focused) {
            state.alert = AppAlert(title: "Falta el vídeo", message: "Selecciona en la tira de la derecha el vídeo que quieres \(mode == .v2v ? "continuar" : mode == .edit ? "editar" : "escalar").")
            return
        }
        if mode == .i2v {
            if let bad = keyframes.first(where: { $0.error != nil }) {
                state.alert = AppAlert(title: "Fotograma no válido", message: "«\(bad.url.lastPathComponent)»: \(bad.error ?? "")")
                return
            }
            guard !keyframes.contains(where: \.isProcessing) else { return }
        }

        let promptText = prompt
        Task {
            do {
                switch mode {
                case .t2v, .i2v, .v2v:
                    var startVideo: String?
                    if mode == .v2v, let url = focused {
                        startVideo = try await Self.encodeVideo(url, maxSeconds: Flux3Video.maxContinueSeconds)
                    }
                    let frames = mode == .i2v
                        ? keyframes.compactMap { k in k.encoded.map { Flux3VideoRequest.Keyframe(image: $0.base64, seconds: useTimestamps ? k.seconds : nil) } }
                        : nil
                    let apiMode: Flux3VideoRequest.Mode = mode == .t2v ? .t2v : (mode == .i2v ? .i2v : .v2v)
                    let body = Flux3VideoRequest(
                        mode: apiMode, prompt: promptText, keyframes: frames, startVideo: startVideo,
                        aspectRatio: aspectRatio, duration: duration, resolution: resolution,
                        generateAudio: generateAudio, draft: draft, safetyTolerance: safety
                    )
                    if let problem = body.validationError() {
                        state.alert = AppAlert(title: "Revisa el vídeo", message: problem)
                        return
                    }
                    let name = draft ? "FLUX 3 Video (borrador)" : "FLUX 3 Video"
                    runner.run(state: state, endpoint: .flux3Video, modelName: name,
                               prompt: promptText.isEmpty ? mode.title : promptText, body: body,
                               referenceCount: frames?.count ?? 0, source: mode == .t2v ? nil : (mode == .i2v ? keyframes.first?.url : focused))
                case .edit:
                    guard let url = focused else { return }
                    guard !promptText.trimmingCharacters(in: .whitespaces).isEmpty else {
                        state.alert = AppAlert(title: "Falta la instrucción", message: "Escribe qué debe cambiar dentro del vídeo.")
                        return
                    }
                    let video = try await Self.encodeVideo(url, maxSeconds: Flux3Video.maxEditSeconds)
                    let body = VideoEditRequest(video: video, prompt: promptText, safetyTolerance: safety)
                    runner.run(state: state, endpoint: .videoEdit, modelName: "Editar vídeo", prompt: promptText,
                               body: body, source: url)
                case .upscale:
                    guard let url = focused else { return }
                    let video = try await Self.encodeVideo(url, maxSeconds: nil, checkUpscaleSize: true)
                    let body = VideoUpscaleRequest(inputVideo: video, prompt: promptText, creativity: creativity,
                                                   upscaleFactor: upscaleFactor, safetyTolerance: safety)
                    runner.run(state: state, endpoint: .videoUpscale, modelName: "Escalar vídeo",
                               prompt: promptText.isEmpty ? "Escalar ×\(upscaleFactor)" : promptText, body: body, source: url)
                }
            } catch {
                state.alert = AppAlert(title: "No se puede enviar el vídeo", message: error.localizedDescription)
            }
        }
    }

    /// Lanza `draft_enhance` con la caché del borrador seleccionado.
    func renderFinal(state: AppState, item: StoredResult) {
        guard let cache = item.record.draftCaches?.first else { return }
        let body = Flux3VideoRequest.draftEnhance(cache: cache, resolution: finalResolution)
        runner.run(state: state, endpoint: .flux3Video, modelName: "FLUX 3 Video (calidad final)",
                   prompt: item.record.prompt, body: body, source: item.fileURL)
    }

    struct VideoInputError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Lee un vídeo local y lo pasa a base64, comprobando antes los límites de la API.
    static func encodeVideo(_ url: URL, maxSeconds: Double?, checkUpscaleSize: Bool = false) async throws -> String {
        guard url.pathExtension.lowercased() == "mp4" else {
            throw VideoInputError(message: "La API solo admite vídeos MP4.")
        }
        if let info = await VideoInfo.load(url) {
            if info.bytes > Flux3Video.maxVideoBytes {
                throw VideoInputError(message: "El vídeo pesa más de 50 MB.")
            }
            if let maxSeconds, info.duration > maxSeconds + 0.05 {
                throw VideoInputError(message: "El vídeo dura \(Int(info.duration.rounded())) s y el máximo aquí es \(Int(maxSeconds)) s. Recórtalo antes.")
            }
            if checkUpscaleSize {
                let long = max(info.size.width, info.size.height), short = min(info.size.width, info.size.height)
                if long > CGFloat(Flux3Video.maxUpscaleSize.width) || short > CGFloat(Flux3Video.maxUpscaleSize.height) {
                    throw VideoInputError(message: "Para escalar, el vídeo debe medir como máximo 2560×1440 (ya es muy grande).")
                }
            }
        }
        let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        return data.base64EncodedString()
    }
}

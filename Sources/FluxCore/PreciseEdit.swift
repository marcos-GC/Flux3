import Foundation

/// Rectángulo en píxeles de la imagen original (origen arriba a la izquierda).
public struct PixelRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// Tipo de región (modo avanzado).
public enum RegionKind: String, CaseIterable, Sendable, Codable {
    /// Cambiar lo que hay dentro de la caja: fila «New» (`from: null`, `tgt_bbox`, `desc`).
    case edit
    /// Crear un elemento nuevo: fila «New» (`from: null`, `src_bbox: null`, `tgt_bbox`, `desc`).
    case new
    /// Mover un elemento: fila «Move» (`src_bbox` origen y `tgt_bbox` destino).
    case move
    /// Mantener la zona sin cambios: fila «Keep» (`src_bbox` igual a `tgt_bbox`).
    case anchor

    public var spanishName: String {
        switch self {
        case .edit: return "Editar"
        case .new: return "Nuevo"
        case .move: return "Mover"
        case .anchor: return "Proteger"
        }
    }
}

/// Una región tal como entra en el prompt.
public struct EditRegionSpec: Sendable, Equatable {
    public var number: Int
    public var kind: RegionKind
    /// Caja origen (Editar, Mover, Proteger).
    public var source: PixelRect?
    /// Caja destino (Nuevo, Mover).
    public var target: PixelRect?
    public var instruction: String
    /// Posición en `images` de la imagen de referencia de esta región (1, 2…), o nil.
    public var referenceImageIndex: Int?
    /// Cajas duplicadas: la misma instrucción (y la misma referencia) en otros sitios.
    /// Valen para Editar, Nuevo y Proteger; en Mover se ignoran.
    public var copies: [PixelRect]

    public init(number: Int, kind: RegionKind = .edit, source: PixelRect? = nil, target: PixelRect? = nil,
                instruction: String, referenceImageIndex: Int? = nil, copies: [PixelRect] = []) {
        self.number = number
        self.copies = copies
        self.kind = kind
        self.source = source
        self.target = target
        self.instruction = instruction
        self.referenceImageIndex = referenceImageIndex
    }

    public var id: String { "region_\(number)" }

    /// Identificador de cada caja: la principal es `region_N` y las copias `region_N_2`, `region_N_3`…
    public func boxID(_ index: Int) -> String { index == 0 ? id : "\(id)_\(index + 1)" }

    /// Si la región aporta algo al prompt (una región de edición sin instrucción no aporta nada).
    public var isUsable: Bool {
        let hasText = !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch kind {
        case .edit: return source != nil && hasText
        case .new: return target != nil && hasText
        case .move: return source != nil && target != nil
        case .anchor: return source != nil
        }
    }
}

/// Construcción del prompt de "Editar con precisión". Las frases replican la herramienta oficial
/// flux-tools.bfl.ai/precise-editing; las filas de cajas siguen la tabla de la documentación de
/// FLUX 3 Image (docs.bfl.ml, «Edit an image box by box»): Keep, Move y New, con
/// `id`, `from`, `src_bbox`, `tgt_bbox` y `desc` en todas.
public enum PreciseEdit {
    /// Texto para la celda central de la cuadrícula 3×3, tal como lo escribe la herramienta
    /// oficial: "…to the marked area <region_1> in the centre of the frame: …".
    public static let centerWord = "centre of the frame"

    public static let closingSentence =
        "Keep everything else — composition, lighting, other subjects, and style — exactly as in the reference image."

    /// Tamaño mínimo fiable según la documentación (~40×25 px).
    public static let minimumReliableSize = (long: 40.0, short: 25.0)

    /// `[y0, x0, y1, x1]` normalizado a 0–1000 y redondeado.
    public static func bbox(_ r: PixelRect, imageWidth: Double, imageHeight: Double) -> [Int] {
        func n(_ v: Double, _ total: Double) -> Int {
            guard total > 0 else { return 0 }
            return min(1000, max(0, Int((v / total * 1000).rounded())))
        }
        return [n(r.y, imageHeight), n(r.x, imageWidth), n(r.maxY, imageHeight), n(r.maxX, imageWidth)]
    }

    /// Posición en la cuadrícula 3×3 según el centro de la caja.
    public static func position(of r: PixelRect, imageWidth: Double, imageHeight: Double) -> String {
        func third(_ v: Double, _ total: Double) -> Int {
            guard total > 0 else { return 1 }
            let f = v / total
            return f < 1.0 / 3.0 ? 0 : (f < 2.0 / 3.0 ? 1 : 2)
        }
        let row = third(r.midY, imageHeight)
        let col = third(r.midX, imageWidth)
        if row == 1 && col == 1 { return centerWord }
        let rows = ["upper", "middle", "lower"]
        let cols = ["left", "middle", "right"]
        return "\(rows[row]) \(cols[col])"
    }

    /// Avisa de cajas muy pequeñas (elementos de ~40×25 px suelen fallar).
    public static func isTooSmall(_ r: PixelRect) -> Bool {
        max(r.width, r.height) < minimumReliableSize.long || min(r.width, r.height) < minimumReliableSize.short
    }

    /// Prompt completo que se envía a FLUX 3 Image (con la imagen original en `images[0]`).
    public static func buildPrompt(
        globalInstruction: String,
        regions: [EditRegionSpec],
        imageWidth: Double,
        imageHeight: Double,
        extraReferenceIndices: [Int] = []
    ) -> String {
        var sentences = ["Edit the first reference image."]
        let global = globalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty {
            sentences.append(endWithPeriod(global))
        }

        var rows: [String] = []
        for region in regions where region.isUsable {
            let text = quoted(region.instruction)
            let instruction = region.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let refClause = region.referenceImageIndex.map { ", using <ref_image_\($0)> as the reference" } ?? ""
            // Fila «New»: genera `desc` en la caja (añade, sustituye o recolorea). Con imagen de
            // referencia, el elemento sale de esa imagen (entera) y va a la caja.
            func newRow(id: String, target: PixelRect) -> String {
                let fromRef = region.referenceImageIndex.map { RowValue.string("ref_image_\($0)") } ?? .null
                let srcRef: RowValue = region.referenceImageIndex == nil ? .null : .bbox([0, 0, 1000, 1000])
                return row([
                    ("id", .string(id)),
                    ("from", fromRef),
                    ("src_bbox", srcRef),
                    ("tgt_bbox", .bbox(bbox(target, imageWidth: imageWidth, imageHeight: imageHeight))),
                    ("desc", .string(instruction)),
                ])
            }
            // Cajas principales más las duplicadas (no en Mover).
            func boxes(_ main: PixelRect) -> [(id: String, rect: PixelRect)] {
                ([main] + region.copies).enumerated().map { (id: region.boxID($0.offset), rect: $0.element) }
            }
            // «<region_1> in the upper left, <region_1_2> in the lower right and <region_1_3> in …»
            func areas(_ list: [(id: String, rect: PixelRect)]) -> String {
                let parts = list.map { "<\($0.id)> in the \(position(of: $0.rect, imageWidth: imageWidth, imageHeight: imageHeight))" }
                guard parts.count > 1 else { return parts.first ?? "" }
                return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
            }
            switch region.kind {
            case .edit:
                let list = boxes(region.source!)
                if list.count == 1 {
                    sentences.append("Apply this edit to the marked area \(areas(list))\(refClause): \(text).")
                } else {
                    sentences.append("Apply this same edit to each of the marked areas \(areas(list))\(refClause): \(text).")
                }
                for box in list { rows.append(newRow(id: box.id, target: box.rect)) }
            case .new:
                let list = boxes(region.target!)
                if list.count == 1 {
                    sentences.append("Add a new element in the marked area \(areas(list))\(refClause): \(text).")
                } else {
                    sentences.append("Add the same new element in each of the marked areas \(areas(list))\(refClause): \(text).")
                }
                for box in list { rows.append(newRow(id: box.id, target: box.rect)) }
            case .move:
                let src = region.source!, tgt = region.target!
                let from = position(of: src, imageWidth: imageWidth, imageHeight: imageHeight)
                let to = position(of: tgt, imageWidth: imageWidth, imageHeight: imageHeight)
                sentences.append("Move the element in the marked area <\(region.id)> from the \(from) to the \(to)"
                    + (instruction.isEmpty ? "." : ": \(quoted(instruction))."))
                rows.append(row([
                    ("id", .string(region.id)),
                    ("from", .string("ref_image_0")),
                    ("src_bbox", .bbox(bbox(src, imageWidth: imageWidth, imageHeight: imageHeight))),
                    ("tgt_bbox", .bbox(bbox(tgt, imageWidth: imageWidth, imageHeight: imageHeight))),
                    ("desc", .string(instruction.isEmpty ? "The element in this area, moved without changing its appearance." : instruction)),
                ]))
            case .anchor:
                let list = boxes(region.source!)
                if list.count == 1 {
                    sentences.append("Keep the marked area \(areas(list)) unchanged.")
                } else {
                    sentences.append("Keep the marked areas \(areas(list)) unchanged.")
                }
                for item in list {
                    let box = bbox(item.rect, imageWidth: imageWidth, imageHeight: imageHeight)
                    rows.append(row([
                        ("id", .string(item.id)),
                        ("from", .string("ref_image_0")),
                        ("src_bbox", .bbox(box)),
                        ("tgt_bbox", .bbox(box)),
                        ("desc", .string(instruction.isEmpty ? "The existing content of this area, kept exactly as it is." : instruction)),
                    ]))
                }
            }
        }

        if !extraReferenceIndices.isEmpty {
            let list = extraReferenceIndices.map { "<ref_image_\($0)>" }.joined(separator: ", ")
            sentences.append("Use \(list) as additional reference.")
        }
        sentences.append(closingSentence)

        var prompt = sentences.joined(separator: " ")
        if !rows.isEmpty {
            prompt += " [" + rows.joined(separator: ",") + "]"
        }
        return prompt
    }

    // MARK: - JSON compacto con el orden de claves de la herramienta oficial

    enum RowValue {
        case string(String)
        case bbox([Int])
        case null
    }

    static func row(_ fields: [(String, RowValue)]) -> String {
        let body = fields.map { key, value -> String in
            let v: String
            switch value {
            case .string(let s): v = jsonString(s)
            case .bbox(let b): v = "[" + b.map(String.init).joined(separator: ",") + "]"
            case .null: v = "null"
            }
            return "\(jsonString(key)):\(v)"
        }.joined(separator: ",")
        return "{\(body)}"
    }

    static func jsonString(_ s: String) -> String {
        let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/") ?? "\"\""
    }

    /// Instrucción entre comillas dobles (las comillas internas pasan a simples).
    static func quoted(_ s: String) -> String {
        "\"" + s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "'") + "\""
    }

    static func endWithPeriod(_ s: String) -> String {
        guard let last = s.last else { return s }
        return ".!?".contains(last) ? s : s + "."
    }
}

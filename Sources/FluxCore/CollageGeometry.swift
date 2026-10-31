import CoreGraphics
import Foundation

/// Cuadrilátero de una capa del collage: sus cuatro esquinas en píxeles del lienzo,
/// en el orden arriba-izquierda, arriba-derecha, abajo-derecha, abajo-izquierda
/// (las esquinas de la imagen original). Mover, escalar, cambiar ancho/alto, girar,
/// voltear y deformar en perspectiva son todo cambios de estas cuatro esquinas.
public struct CollageQuad: Equatable, Sendable {
    public var corners: [CGPoint]

    public init(corners: [CGPoint]) {
        precondition(corners.count == 4)
        self.corners = corners
    }

    /// Rectángulo sin deformar.
    public init(rect r: CGRect) {
        corners = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
        ]
    }

    public var topLeft: CGPoint { corners[0] }
    public var topRight: CGPoint { corners[1] }
    public var bottomRight: CGPoint { corners[2] }
    public var bottomLeft: CGPoint { corners[3] }

    public var center: CGPoint {
        CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
    }

    public var boundingBox: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Ancho y alto aproximados (el lado más largo de cada pareja).
    public var approximateSize: CGSize {
        CGSize(width: max(corners[0].distance(to: corners[1]), corners[3].distance(to: corners[2])),
               height: max(corners[0].distance(to: corners[3]), corners[1].distance(to: corners[2])))
    }

    /// Lados: 0 arriba, 1 derecha, 2 abajo, 3 izquierda. Devuelve los índices de sus dos esquinas.
    public static func edgeCorners(_ edge: Int) -> (Int, Int) {
        (edge % 4, (edge + 1) % 4)
    }

    public func edgeMidpoint(_ edge: Int) -> CGPoint {
        let (a, b) = Self.edgeCorners(edge)
        return corners[a].midpoint(corners[b])
    }

    // MARK: Transformaciones

    public func translated(by d: CGVector) -> CollageQuad {
        CollageQuad(corners: corners.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) })
    }

    /// Escala proporcional arrastrando la esquina `index`: la esquina opuesta queda fija.
    public func scaledFromCorner(_ index: Int, to pointer: CGPoint, minSide: CGFloat = 8) -> CollageQuad {
        let anchor = corners[(index + 2) % 4]
        let original = corners[index] - anchor
        let lengthSquared = original.dx * original.dx + original.dy * original.dy
        guard lengthSquared > 0 else { return self }
        let toPointer = pointer - anchor
        var s = (toPointer.dx * original.dx + toPointer.dy * original.dy) / lengthSquared
        let size = approximateSize
        let minScale = minSide / max(1, min(size.width, size.height))
        s = max(s, minScale)
        return CollageQuad(corners: corners.map { anchor + ($0 - anchor) * s })
    }

    /// Estira o encoge arrastrando el lado `edge` (más ancho/estrecho, más alto/bajo).
    /// El lado opuesto queda fijo; se mueve solo en perpendicular a él.
    public func stretchedEdge(_ edge: Int, by delta: CGVector, minSide: CGFloat = 8) -> CollageQuad {
        let opposite = edgeMidpoint((edge + 2) % 4)
        let mid = edgeMidpoint(edge)
        let axis = mid - opposite
        let length = axis.length
        guard length > 0 else { return self }
        let dir = axis * (1 / length)
        var d = delta.dx * dir.dx + delta.dy * dir.dy
        d = max(d, minSide - length)
        let (a, b) = Self.edgeCorners(edge)
        var c = corners
        c[a] = c[a] + dir * d
        c[b] = c[b] + dir * d
        return CollageQuad(corners: c)
    }

    /// Gira alrededor del centro (en radianes, sentido horario en pantalla).
    public func rotated(by angle: CGFloat, around pivot: CGPoint? = nil) -> CollageQuad {
        let p = pivot ?? center
        let cosA = cos(angle), sinA = sin(angle)
        return CollageQuad(corners: corners.map { point in
            let v = point - p
            return CGPoint(x: p.x + v.dx * cosA - v.dy * sinA, y: p.y + v.dx * sinA + v.dy * cosA)
        })
    }

    /// Perspectiva / distorsión: mueve una sola esquina.
    public func movingCorner(_ index: Int, to point: CGPoint) -> CollageQuad {
        var c = corners
        c[index] = point
        let candidate = CollageQuad(corners: c)
        // Una forma cruzada o vuelta del revés no se puede dibujar bien: se ignora el cambio.
        return candidate.isConvex ? candidate : self
    }

    /// Espejo horizontal (izquierda ↔ derecha de la imagen).
    public var flippedHorizontally: CollageQuad {
        CollageQuad(corners: [corners[1], corners[0], corners[3], corners[2]])
    }

    /// Espejo vertical (arriba ↔ abajo de la imagen).
    public var flippedVertically: CollageQuad {
        CollageQuad(corners: [corners[3], corners[2], corners[1], corners[0]])
    }

    public func scaled(by factor: CGFloat) -> CollageQuad {
        CollageQuad(corners: corners.map { CGPoint(x: $0.x * factor, y: $0.y * factor) })
    }

    // MARK: Consultas

    /// Convexo y sin cruzarse (todas las vueltas en el mismo sentido).
    public var isConvex: Bool {
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
            let cross = (b - a).cross(c - b)
            if abs(cross) < 1e-9 { return false }
            if sign == 0 { sign = cross > 0 ? 1 : -1 } else if (cross > 0 ? 1 : -1) != sign { return false }
        }
        return true
    }

    /// Si un punto está dentro (vale para cualquier cuadrilátero simple).
    public func contains(_ p: CGPoint) -> Bool {
        var inside = false
        var j = 3
        for i in 0..<4 {
            let a = corners[i], b = corners[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Homografía que lleva el cuadrado unidad (u, v ∈ 0…1) a este cuadrilátero:
    /// x = (a·u + b·v + c) / (g·u + h·v + 1), y = (d·u + e·v + f) / (g·u + h·v + 1).
    public var homography: Homography {
        let (x0, y0) = (corners[0].x, corners[0].y)
        let (x1, y1) = (corners[1].x, corners[1].y)
        let (x2, y2) = (corners[2].x, corners[2].y)
        let (x3, y3) = (corners[3].x, corners[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        if abs(dx3) < 1e-9 && abs(dy3) < 1e-9 {
            return Homography(a: x1 - x0, b: x3 - x0, c: x0, d: y1 - y0, e: y3 - y0, f: y0, g: 0, h: 0)
        }
        let det = dx1 * dy2 - dx2 * dy1
        guard abs(det) > 1e-12 else {
            return Homography(a: x1 - x0, b: x3 - x0, c: x0, d: y1 - y0, e: y3 - y0, f: y0, g: 0, h: 0)
        }
        let g = (dx3 * dy2 - dx2 * dy3) / det
        let h = (dx1 * dy3 - dx3 * dy1) / det
        return Homography(
            a: x1 - x0 + g * x1, b: x3 - x0 + h * x3, c: x0,
            d: y1 - y0 + g * y1, e: y3 - y0 + h * y3, f: y0,
            g: g, h: h
        )
    }
}

/// Transformación proyectiva del plano (de una imagen a su cuadrilátero).
public struct Homography: Equatable, Sendable {
    public var a, b, c, d, e, f, g, h: CGFloat

    public func apply(u: CGFloat, v: CGFloat) -> CGPoint {
        let w = g * u + h * v + 1
        return CGPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }

    /// Lo contrario: de un punto del lienzo a (u, v) dentro de la imagen (0…1 si cae dentro).
    /// Sirve para pintar con la goma sobre una capa girada o en perspectiva.
    public func invert(_ p: CGPoint) -> CGPoint? {
        // Adjunta de [[a b c] [d e f] [g h 1]]; el determinante se cancela al dividir.
        let r0 = (e - f * h, c * h - b, b * f - c * e)
        let r1 = (f * g - d, a - c * g, c * d - a * f)
        let r2 = (d * h - e * g, b * g - a * h, a * e - b * d)
        let u = r0.0 * p.x + r0.1 * p.y + r0.2
        let v = r1.0 * p.x + r1.1 * p.y + r1.2
        let w = r2.0 * p.x + r2.1 * p.y + r2.2
        guard abs(w) > 1e-12 else { return nil }
        return CGPoint(x: u / w, y: v / w)
    }
}

// MARK: - Proyecto guardado

/// Lo que se guarda de un collage para retomarlo otro día (`proyecto.json` dentro de su carpeta,
/// junto a la base y las imágenes de cada capa en PNG).
public struct CollageProjectFile: Codable, Equatable, Sendable {
    public struct Layer: Codable, Equatable, Sendable {
        public var id: UUID
        /// Archivo original del objeto (para enviarlo como referencia, si sigue existiendo).
        public var source: String
        /// Imagen de la capa (ya recortada si se quitó el fondo), dentro de la carpeta del proyecto.
        public var imageFile: String
        /// Máscara de la goma (gris: blanco = se ve), si se ha borrado algo.
        public var maskFile: String?
        /// Esquinas [x, y] en píxeles de la base: arriba-izq., arriba-der., abajo-der., abajo-izq.
        public var corners: [[Double]]
        public var opacity: Double
        public var visible: Bool
        public var cutOut: Bool
        /// Recorte automático sin retocar y ajustes de su borde (opcionales: versiones anteriores no los tienen).
        public var autoMaskFile: String?
        public var maskEdge: Double?
        public var maskFeather: Double?

        public init(id: UUID, source: String, imageFile: String, maskFile: String?, corners: [[Double]],
                    opacity: Double, visible: Bool, cutOut: Bool,
                    autoMaskFile: String? = nil, maskEdge: Double? = nil, maskFeather: Double? = nil) {
            self.autoMaskFile = autoMaskFile
            self.maskEdge = maskEdge
            self.maskFeather = maskFeather
            self.id = id
            self.source = source
            self.imageFile = imageFile
            self.maskFile = maskFile
            self.corners = corners
            self.opacity = opacity
            self.visible = visible
            self.cutOut = cutOut
        }

        public var quad: CollageQuad? {
            guard corners.count == 4, corners.allSatisfy({ $0.count == 2 }) else { return nil }
            return CollageQuad(corners: corners.map { CGPoint(x: $0[0], y: $0[1]) })
        }
    }

    public var version = 1
    public var name: String
    public var created: Date
    public var modified: Date
    public var baseFile: String
    public var baseSource: String?
    public var extraPrompt: String
    public var resolution: String
    public var sendOriginals: Bool
    public var layers: [Layer]

    public init(name: String, created: Date, modified: Date, baseFile: String, baseSource: String?,
                extraPrompt: String, resolution: String, sendOriginals: Bool, layers: [Layer]) {
        self.name = name
        self.created = created
        self.modified = modified
        self.baseFile = baseFile
        self.baseSource = baseSource
        self.extraPrompt = extraPrompt
        self.resolution = resolution
        self.sendOriginals = sendOriginals
        self.layers = layers
    }

    public static let fileName = "proyecto.json"
    public static let folderExtension = "fluxcollage"

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> CollageProjectFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CollageProjectFile.self, from: data)
    }
}

extension CollageQuad {
    public var cornerArrays: [[Double]] { corners.map { [Double($0.x), Double($0.y)] } }
}

// MARK: - Ayudas de vectores

extension CGPoint {
    public static func - (l: CGPoint, r: CGPoint) -> CGVector { CGVector(dx: l.x - r.x, dy: l.y - r.y) }
    public static func + (l: CGPoint, r: CGVector) -> CGPoint { CGPoint(x: l.x + r.dx, y: l.y + r.dy) }
    public func distance(to other: CGPoint) -> CGFloat { (self - other).length }
    public func midpoint(_ other: CGPoint) -> CGPoint { CGPoint(x: (x + other.x) / 2, y: (y + other.y) / 2) }
}

extension CGVector {
    public static func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    public var length: CGFloat { (dx * dx + dy * dy).squareRoot() }
    public func cross(_ o: CGVector) -> CGFloat { dx * o.dy - dy * o.dx }
}

// MARK: - Prompt de «Hacer realista»

public enum CollagePrompt {
    /// Instrucción para que FLUX 3 Image convierta el collage (image 1) en una foto realista.
    public static func build(extra: String, referenceCount: Int) -> String {
        var parts = [
            "Turn the rough photo collage in image 1 into a single coherent, photorealistic photograph.",
            "Keep the exact composition: the background scene stays the same and every pasted object keeps its position, size, orientation and perspective as placed in the collage.",
            "Integrate each object naturally into the scene: match the lighting direction, color temperature and exposure, add realistic contact shadows and reflections, and clean up cut-out edges, halos and collage artifacts.",
            "Do not add, remove or rearrange objects.",
        ]
        if referenceCount > 0 {
            let list = (2...(referenceCount + 1)).map { "image \($0)" }.joined(separator: ", ")
            parts.append("\(list) show the original objects used in the collage; keep their real shape, materials, textures and printed details.")
        }
        let note = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note.hasSuffix(".") ? note : note + ".")
        }
        return parts.joined(separator: " ")
    }
}

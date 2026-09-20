import Foundation

public enum DrawingBrush: String, CaseIterable, Codable, Hashable, Sendable {
    case pen, crayon, neon, spray, eraser
}

public struct DrawingPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init?(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return nil }
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey { case x, y }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let x = try values.decode(Double.self, forKey: .x)
        let y = try values.decode(Double.self, forKey: .y)
        guard let result = Self(x: x, y: y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: values,
                                                   debugDescription: "描画座標が不正です")
        }
        self = result
    }
}

public struct DrawingColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init?(red: Double, green: Double, blue: Double, alpha: Double) {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let red = try values.decode(Double.self, forKey: .red)
        let green = try values.decode(Double.self, forKey: .green)
        let blue = try values.decode(Double.self, forKey: .blue)
        let alpha = try values.decode(Double.self, forKey: .alpha)
        guard let result = Self(red: red, green: green, blue: blue, alpha: alpha) else {
            throw DecodingError.dataCorruptedError(forKey: .red, in: values,
                                                   debugDescription: "描画色が不正です")
        }
        self = result
    }
}

public struct DrawingStroke: Codable, Equatable, Sendable {
    public let id: UUID
    public let brush: DrawingBrush
    public let color: DrawingColor
    public let width: Double
    public let opacity: Double
    public let points: [DrawingPoint]
    public let randomSeed: UInt64

    public init?(id: UUID, brush: DrawingBrush, color: DrawingColor, width: Double,
                 opacity: Double, points: [DrawingPoint], randomSeed: UInt64) {
        guard width.isFinite, (0...1_000).contains(width), width > 0,
              opacity.isFinite, (0...1).contains(opacity),
              !points.isEmpty, points.count <= 100_000 else { return nil }
        self.id = id
        self.brush = brush
        self.color = color
        self.width = width
        self.opacity = opacity
        self.points = points
        self.randomSeed = randomSeed
    }

    private enum CodingKeys: String, CodingKey {
        case id, brush, color, width, opacity, points, randomSeed
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let result = Self(
            id: try values.decode(UUID.self, forKey: .id),
            brush: try values.decode(DrawingBrush.self, forKey: .brush),
            color: try values.decode(DrawingColor.self, forKey: .color),
            width: try values.decode(Double.self, forKey: .width),
            opacity: try values.decode(Double.self, forKey: .opacity),
            points: try values.decode([DrawingPoint].self, forKey: .points),
            randomSeed: try values.decode(UInt64.self, forKey: .randomSeed)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: values,
                                                   debugDescription: "筆跡が不正です")
        }
        self = result
    }
}

public struct DrawingDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let strokes: [DrawingStroke]

    public init?(schemaVersion: Int = DrawingDocument.currentSchemaVersion,
                 pixelWidth: Int, pixelHeight: Int, strokes: [DrawingStroke]) {
        guard schemaVersion == Self.currentSchemaVersion,
              pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 10_000, pixelHeight <= 10_000,
              Int64(pixelWidth) * Int64(pixelHeight) <= 25_000_000,
              strokes.count <= 10_000,
              strokes.reduce(0, { $0 + $1.points.count }) <= 100_000,
              Set(strokes.map(\.id)).count == strokes.count,
              strokes.allSatisfy({ stroke in
                  stroke.points.allSatisfy { point in
                      point.x >= 0 && point.x < Double(pixelWidth) &&
                      point.y >= 0 && point.y < Double(pixelHeight)
                  }
              }) else { return nil }
        self.schemaVersion = schemaVersion
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.strokes = strokes
    }

    public func replacingStrokes(_ strokes: [DrawingStroke]) -> DrawingDocument? {
        DrawingDocument(schemaVersion: schemaVersion, pixelWidth: pixelWidth,
                        pixelHeight: pixelHeight, strokes: strokes)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pixelWidth, pixelHeight, strokes
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let result = Self(
            schemaVersion: try values.decode(Int.self, forKey: .schemaVersion),
            pixelWidth: try values.decode(Int.self, forKey: .pixelWidth),
            pixelHeight: try values.decode(Int.self, forKey: .pixelHeight),
            strokes: try values.decode([DrawingStroke].self, forKey: .strokes)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .strokes, in: values,
                                                   debugDescription: "描画文書が不正です")
        }
        self = result
    }
}

import Foundation
import MapGrapherCore

/// 一筆単位の履歴。描画途中の各点ではビットマップを複製しない。
struct DrawingHistory {
    private(set) var document: DrawingDocument
    private var undone: [DrawingStroke] = []

    init(document: DrawingDocument) { self.document = document }

    var canUndo: Bool { !document.strokes.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    mutating func append(_ stroke: DrawingStroke) {
        guard let updated = document.replacingStrokes(document.strokes + [stroke]) else { return }
        document = updated
        undone.removeAll()
    }

    mutating func undo() {
        guard let last = document.strokes.last,
              let updated = document.replacingStrokes(Array(document.strokes.dropLast())) else { return }
        document = updated
        undone.append(last)
    }

    mutating func redo() {
        guard let next = undone.last,
              let updated = document.replacingStrokes(document.strokes + [next]) else { return }
        document = updated
        undone.removeLast()
    }
}

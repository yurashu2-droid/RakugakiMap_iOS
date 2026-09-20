import CoreGraphics
import SwiftUI
import MapGrapherCore

struct DrawingCanvasView: View {
    let baseImage: CGImage
    let onDocumentChange: (DrawingDocument) -> Void

    @State private var history: DrawingHistory
    @State private var renderer = DrawingRenderer()
    @State private var renderedLayer: CGImage?
    @State private var currentPoints: [DrawingPoint] = []
    @State private var strokeSeed: UInt64 = 0
    @State private var strokeRejected = false
    @State private var suppressStrokeUntilLift = false
    @State private var selectedBrush: DrawingBrush = .pen
    @State private var selectedColor = DrawingColor(red: 0.79, green: 0.26, blue: 0.31, alpha: 1)!
    @State private var brushWidth: Double = 12
    @State private var strokeOpacity: Double = 1
    @State private var isNavigating = false
    @State private var zoom: Double = 1
    @State private var zoomStart: Double = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var renderError: String?

    init(baseImage: CGImage, document: DrawingDocument,
         onDocumentChange: @escaping (DrawingDocument) -> Void) {
        self.baseImage = baseImage
        self.onDocumentChange = onDocumentChange
        _history = State(initialValue: DrawingHistory(document: document))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let fit = min(geometry.size.width / CGFloat(history.document.pixelWidth),
                              geometry.size.height / CGFloat(history.document.pixelHeight))
                let imageSize = CGSize(width: CGFloat(history.document.pixelWidth) * fit,
                                       height: CGFloat(history.document.pixelHeight) * fit)
                ZStack {
                    Color(.systemGroupedBackground)
                    Image(decorative: baseImage, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageSize.width, height: imageSize.height)
                        .overlay {
                            if let renderedLayer {
                                Image(decorative: renderedLayer, scale: 1, orientation: .up)
                                    .resizable()
                                    .interpolation(.high)
                            }
                        }
                        .scaleEffect(zoom)
                        .offset(pan)
                    liveStroke(in: geometry.size)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
                .simultaneousGesture(magnifyGesture)
                .clipped()
            }
            if let renderError {
                Text(renderError).foregroundStyle(.red).accessibilityLabel(renderError)
            }
            toolbar
        }
        .onAppear(perform: refreshLayer)
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Button("戻す", systemImage: "arrow.uturn.backward") { history.undo(); changed() }
                    .disabled(!history.canUndo)
                Button("やり直す", systemImage: "arrow.uturn.forward") { history.redo(); changed() }
                    .disabled(!history.canRedo)
                Spacer()
                Button(isNavigating ? "描く" : "移動", systemImage: isNavigating ? "pencil" : "hand.draw") {
                    isNavigating.toggle()
                    currentPoints.removeAll()
                }
                Button("拡大を戻す", systemImage: "arrow.up.left.and.arrow.down.right") {
                    zoom = 1
                    zoomStart = 1
                    pan = .zero
                    panStart = .zero
                }
            }
            .buttonStyle(.bordered)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(DrawingBrush.allCases, id: \.self) { brush in
                        Button(brush.label) { selectedBrush = brush; isNavigating = false }
                            .buttonStyle(.bordered)
                            .tint(selectedBrush == brush ? .accentColor : .gray)
                    }
                }
            }
            HStack {
                ForEach(Array(palette.enumerated()), id: \.offset) { item in
                    let color = item.element
                    Button {
                        selectedColor = color
                        isNavigating = false
                    } label: {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 32, height: 32)
                            .frame(width: 44, height: 44)
                            .overlay {
                                if color == selectedColor {
                                    Circle().strokeBorder(.primary, lineWidth: 2).padding(2)
                                }
                            }
                    }
                    .accessibilityLabel("描画色")
                }
            }
            Slider(value: $brushWidth, in: 2...60) {
                Text("線の太さ")
            }
            Slider(value: $strokeOpacity, in: 0.1...1) {
                Text("不透明度")
            }
        }
        .padding(.horizontal)
    }

    private func liveStroke(in size: CGSize) -> some View {
        let transform = drawingTransform(for: size)
        return Path { path in
            guard let transform, let first = currentPoints.first else { return }
            let firstView = transform.viewPoint(fromImage: first)
            path.move(to: CGPoint(x: CGFloat(firstView.x), y: CGFloat(firstView.y)))
            for point in currentPoints.dropFirst() {
                let view = transform.viewPoint(fromImage: point)
                path.addLine(to: CGPoint(x: CGFloat(view.x), y: CGFloat(view.y)))
            }
            if currentPoints.count == 1 {
                path.addLine(to: CGPoint(x: CGFloat(firstView.x + 0.01), y: CGFloat(firstView.y)))
            }
        }
        .stroke(selectedBrush == .eraser ? Color.gray.opacity(0.5) :
                Color(red: selectedColor.red, green: selectedColor.green,
                      blue: selectedColor.blue).opacity(strokeOpacity),
                style: StrokeStyle(lineWidth: CGFloat(brushWidth) * CGFloat(transformScale(for: size)),
                                   lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
    }

    private func drawingTransform(for size: CGSize) -> DrawingTransform? {
        DrawingTransform(imageWidth: Double(history.document.pixelWidth),
                         imageHeight: Double(history.document.pixelHeight),
                         viewportWidth: Double(size.width), viewportHeight: Double(size.height),
                         zoom: zoom, panX: Double(pan.width), panY: Double(pan.height))
    }

    private func transformScale(for size: CGSize) -> Double {
        min(Double(size.width) / Double(history.document.pixelWidth),
            Double(size.height) / Double(history.document.pixelHeight)) * zoom
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isNavigating {
                    pan = CGSize(width: panStart.width + value.translation.width,
                                 height: panStart.height + value.translation.height)
                    return
                }
                guard !suppressStrokeUntilLift else { return }
                guard !strokeRejected, let transform = drawingTransform(for: size) else { return }
                guard let point = DrawingPoint(x: Double(value.location.x), y: Double(value.location.y)),
                      let pixel = transform.imagePoint(fromView: point) else {
                    if currentPoints.isEmpty { strokeRejected = true }
                    return
                }
                if currentPoints.isEmpty { strokeSeed = UInt64.random(in: UInt64.min...UInt64.max) }
                if let last = currentPoints.last, hypot(last.x - pixel.x, last.y - pixel.y) < 0.25 {
                    return
                }
                currentPoints.append(pixel)
            }
            .onEnded { _ in
                if isNavigating { panStart = pan }
                else if !suppressStrokeUntilLift, !currentPoints.isEmpty,
                        let stroke = DrawingStroke(id: UUID(), brush: selectedBrush,
                                                   color: selectedColor, width: brushWidth,
                                                   opacity: strokeOpacity, points: currentPoints,
                                                   randomSeed: strokeSeed) {
                    history.append(stroke)
                    changed()
                }
                currentPoints.removeAll()
                strokeRejected = false
                suppressStrokeUntilLift = false
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isNavigating {
                    currentPoints.removeAll()
                    suppressStrokeUntilLift = true
                }
                zoom = min(8, max(0.5, zoomStart * Double(value.magnification)))
            }
            .onEnded { _ in zoomStart = zoom }
    }

    private var palette: [DrawingColor] {
        [
            DrawingColor(red: 0.79, green: 0.26, blue: 0.31, alpha: 1)!,
            DrawingColor(red: 0.1, green: 0.15, blue: 0.24, alpha: 1)!,
            DrawingColor(red: 0.12, green: 0.55, blue: 0.48, alpha: 1)!,
            DrawingColor(red: 0.97, green: 0.68, blue: 0.18, alpha: 1)!,
            DrawingColor(red: 1, green: 1, blue: 1, alpha: 1)!
        ]
    }

    private func changed() {
        refreshLayer()
        onDocumentChange(history.document)
    }

    private func refreshLayer() {
        do {
            renderedLayer = try renderer.render(document: history.document)
            renderError = nil
        } catch {
            renderedLayer = nil
            renderError = "描画を表示できません"
        }
    }
}

private extension DrawingBrush {
    var label: String {
        switch self {
        case .pen: "ペン"
        case .crayon: "クレヨン"
        case .neon: "ネオン"
        case .spray: "スプレー"
        case .eraser: "消しゴム"
        }
    }
}

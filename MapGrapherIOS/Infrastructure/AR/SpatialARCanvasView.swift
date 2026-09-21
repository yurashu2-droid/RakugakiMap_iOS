import RealityKit
import SwiftUI

@MainActor
struct SpatialARCanvasView: UIViewRepresentable {
    @ObservedObject var driver: SpatialARDrawingDriver

    func makeCoordinator() -> Coordinator {
        Coordinator(driver: driver)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.environment.sceneUnderstanding.options = []
        driver.attach(view: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.driver.detach(view: view)
    }

    @MainActor
    final class Coordinator {
        let driver: SpatialARDrawingDriver

        init(driver: SpatialARDrawingDriver) {
            self.driver = driver
        }
    }
}

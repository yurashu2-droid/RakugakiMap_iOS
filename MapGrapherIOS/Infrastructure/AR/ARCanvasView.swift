import RealityKit
import SwiftUI
import UIKit

/// ARViewの生成と所有をこのSwiftUI境界に限定する。
@MainActor
struct ARCanvasView: UIViewRepresentable {
    let driver: ARSessionDriver

    func makeCoordinator() -> Coordinator {
        Coordinator(driver: driver)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )
        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didTap(_:))
        )
        view.addGestureRecognizer(recognizer)
        driver.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.driver.detach(view: uiView)
    }

    @MainActor
    final class Coordinator: NSObject {
        let driver: ARSessionDriver

        init(driver: ARSessionDriver) {
            self.driver = driver
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            driver.place(at: recognizer.location(in: view))
        }
    }
}

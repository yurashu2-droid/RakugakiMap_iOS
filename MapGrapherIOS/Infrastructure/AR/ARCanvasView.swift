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
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didTap(_:))
        )
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didPan(_:))
        )
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didPinch(_:))
        )
        let rotation = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didRotate(_:))
        )
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(rotation)
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

        @objc func didPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view,
                  recognizer.state == .began || recognizer.state == .changed else {
                return
            }
            driver.movePlacement(to: recognizer.location(in: view))
        }

        @objc func didPinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                return
            }
            driver.scalePlacement(by: recognizer.scale)
            recognizer.scale = 1
        }

        @objc func didRotate(_ recognizer: UIRotationGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                return
            }
            driver.rotatePlacement(by: recognizer.rotation)
            recognizer.rotation = 0
        }
    }
}

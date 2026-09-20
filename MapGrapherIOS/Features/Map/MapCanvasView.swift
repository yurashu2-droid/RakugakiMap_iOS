@preconcurrency import MapKit
import SwiftUI
import UIKit
import MapGrapherCore

@MainActor
struct MapCanvasView: UIViewRepresentable {
    let photos: [Photo]
    let center: GeoPoint?
    let assetLoader: PrivateAssetLoader?
    let sessionContext: SessionContext?
    let showsUserLocation: Bool
    let onSelect: (Photo) -> Void
    let onRegionSettled: (GeoPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            photos: photos,
            assetLoader: assetLoader,
            sessionContext: sessionContext,
            onSelect: onSelect,
            onRegionSettled: onRegionSettled
        )
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = showsUserLocation
        mapView.register(
            PhotoPinAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.annotationReuseIdentifier
        )
        context.coordinator.update(photos: photos, center: center, mapView: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.photos = photos
        context.coordinator.onSelect = onSelect
        context.coordinator.onRegionSettled = onRegionSettled
        context.coordinator.update(photos: photos, center: center, mapView: mapView)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        static let annotationReuseIdentifier = "map.photo-pin"

        var photos: [Photo]
        let assetLoader: PrivateAssetLoader?
        let sessionContext: SessionContext?
        var onSelect: (Photo) -> Void
        var onRegionSettled: (GeoPoint) -> Void

        private var hasConfiguredInitialRegion = false
        private var settleTask: Task<Void, Never>?

        init(
            photos: [Photo],
            assetLoader: PrivateAssetLoader?,
            sessionContext: SessionContext?,
            onSelect: @escaping (Photo) -> Void,
            onRegionSettled: @escaping (GeoPoint) -> Void
        ) {
            self.photos = photos
            self.assetLoader = assetLoader
            self.sessionContext = sessionContext
            self.onSelect = onSelect
            self.onRegionSettled = onRegionSettled
        }

        func update(photos: [Photo], center: GeoPoint?, mapView: MKMapView) {
            let existing = mapView.annotations.compactMap { $0 as? PhotoAnnotation }
            let existingIDs = Set(existing.map(\.photoID))
            let incomingIDs = Set(photos.map(\.id))

            let removed = existing.filter { !incomingIDs.contains($0.photoID) }
            if !removed.isEmpty {
                mapView.removeAnnotations(removed)
            }

            let additions = photos
                .filter { !existingIDs.contains($0.id) }
                .map(PhotoAnnotation.init(photo:))
            if !additions.isEmpty {
                mapView.addAnnotations(additions)
            }

            guard !hasConfiguredInitialRegion else { return }
            let initialCenter = center ?? photos.first?.location
            guard let initialCenter else { return }
            let coordinate = CLLocationCoordinate2D(
                latitude: initialCenter.latitude,
                longitude: initialCenter.longitude
            )
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_000,
                    longitudinalMeters: 1_000
                ),
                animated: false
            )
            hasConfiguredInitialRegion = true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let reuseID = "map.player"
                return mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                    ?? PlayerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            }
            guard let annotation = annotation as? PhotoAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(
                      withIdentifier: Self.annotationReuseIdentifier,
                      for: annotation
                  ) as? PhotoPinAnnotationView,
                  let photo = photos.first(where: { $0.id == annotation.photoID }) else {
                return nil
            }
            view.configure(photo: photo, assetLoader: assetLoader, context: sessionContext)
            view.clusteringIdentifier = Self.annotationReuseIdentifier
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PhotoAnnotation,
                  let photo = photos.first(where: { $0.id == annotation.photoID }) else {
                return
            }
            onSelect(photo)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            settleTask?.cancel()
            let region = mapView.region
            settleTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
                guard let self,
                      !Task.isCancelled,
                      let point = GeoPoint(
                          latitude: region.center.latitude,
                          longitude: region.center.longitude
                      ) else { return }
                self.onRegionSettled(point)
            }
        }
    }
}

private final class PhotoAnnotation: NSObject, MKAnnotation {
    let photoID: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(photo: Photo) {
        photoID = photo.id
        coordinate = CLLocationCoordinate2D(
            latitude: photo.location.latitude,
            longitude: photo.location.longitude
        )
        title = photo.title
        subtitle = nil
        super.init()
    }
}

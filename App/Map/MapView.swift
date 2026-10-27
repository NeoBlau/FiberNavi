import SwiftUI
import MapLibre

/// Обёртка над MLNMapView. Стиль, картинки и наклон камеры приходят из темы.
struct MapView: UIViewRepresentable {
    let styleURL: URL
    let images: [String: UIImage]
    let pitch: Double
    let camera: CameraController
    /// Передаётся значением, чтобы SwiftUI вызывал updateUIView при смене режима.
    let mode: CameraController.Mode

    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.compassView.compassVisibility = .adaptive
        map.setCenter(AppConfig.defaultCenter, zoomLevel: AppConfig.defaultZoom, animated: false)
        context.coordinator.images = images
        context.coordinator.pitch = pitch
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.images = images
        if coordinator.pitch != pitch {
            coordinator.pitch = pitch
            coordinator.applyPitch(map)
        }
        if map.styleURL != styleURL {
            map.styleURL = styleURL
        }
        let tracking: MLNUserTrackingMode = switch mode {
        case .free: .none
        case .followCourse: .followWithCourse
        case .followNorthUp: .follow
        }
        if map.userTrackingMode != tracking {
            map.setUserTrackingMode(tracking, animated: true, completionHandler: nil)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let camera: CameraController
        var images: [String: UIImage] = [:]
        var pitch: Double = 0

        init(camera: CameraController) {
            self.camera = camera
        }

        func applyPitch(_ map: MLNMapView) {
            let cam = map.camera
            cam.pitch = pitch
            map.setCamera(cam, animated: true)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            for (name, image) in images {
                style.setImage(image, forName: name)
            }
            applyPitch(mapView)
        }

        /// Страховка: стиль сослался на картинку, которой нет — отдаём нейтральную метку.
        func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            images[imageName] ?? images["blip.generic"]
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            // MapLibre сбрасывает трекинг в .none, когда пользователь двигает карту.
            if mode == .none {
                camera.userDidPan()
            }
        }
    }
}

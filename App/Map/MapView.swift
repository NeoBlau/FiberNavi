import SwiftUI
import MapLibre

/// Обёртка над MLNMapView. Стиль позже будет подставлять ThemeManager.
struct MapView: UIViewRepresentable {
    let styleURL: URL
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
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
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

        init(camera: CameraController) {
            self.camera = camera
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            // MapLibre сбрасывает трекинг в .none, когда пользователь двигает карту.
            if mode == .none {
                camera.userDidPan()
            }
        }
    }
}

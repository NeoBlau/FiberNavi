import SwiftUI
import MapLibre

/// Обёртка над MLNMapView. Стиль, картинки и наклон камеры приходят из темы,
/// маршрут и стрелка — из навигации.
struct MapView: UIViewRepresentable {
    let styleURL: URL
    let images: [String: UIImage]
    let pitch: Double
    let routeStyle: RouteStyle
    let overlay: MapOverlayState
    let camera: CameraController
    /// Передаётся значением, чтобы SwiftUI вызывал updateUIView при смене режима.
    let mode: CameraController.Mode
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.compassView.compassVisibility = .adaptive
        map.setCenter(AppConfig.defaultCenter, zoomLevel: AppConfig.defaultZoom, animated: false)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        map.addGestureRecognizer(press)
        let c = context.coordinator
        c.images = images
        c.pitch = pitch
        c.routeStyle = routeStyle
        c.overlay = overlay
        c.onLongPress = onLongPress
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.images = images
        c.onLongPress = onLongPress
        if c.pitch != pitch {
            c.pitch = pitch
            c.applyPitch(map)
        }
        if map.styleURL != styleURL {
            c.routeStyle = routeStyle
            map.styleURL = styleURL
        } else if c.routeStyle != routeStyle, let style = map.style {
            c.routeStyle = routeStyle
            c.reinstallLayers(style)
        }
        if c.overlay != overlay {
            let routesChanged = c.overlay.routes != overlay.routes
            c.overlay = overlay
            if let style = map.style { RouteLayers.update(in: style, state: overlay) }
            if routesChanged, overlay.puck == nil, !overlay.routes.isEmpty {
                Self.fit(map, routes: overlay.routes)
            }
        }

        // Во время ведения рисуем свою стрелку на привязанной позиции и ведём камеру сами.
        let navigating = overlay.puck != nil
        if map.showsUserLocation == navigating {
            map.showsUserLocation = !navigating
        }
        if navigating, let puck = overlay.puck {
            if mode != .free {
                let direction = mode == .followNorthUp ? 0 : overlay.puckCourse
                map.setCenter(puck, zoomLevel: overlay.followZoom, direction: direction, animated: true)
            }
        } else {
            let tracking: MLNUserTrackingMode = switch mode {
            case .free: .none
            case .followCourse: .followWithCourse
            case .followNorthUp: .follow
            }
            if map.userTrackingMode != tracking {
                map.setUserTrackingMode(tracking, animated: true, completionHandler: nil)
            }
        }
    }

    /// Показать все варианты маршрута целиком (экран выбора маршрута).
    static func fit(_ map: MLNMapView, routes: [Route]) {
        let all = routes.flatMap(\.coordinates)
        guard let first = all.first else { return }
        var sw = first, ne = first
        for c in all {
            sw.latitude = min(sw.latitude, c.latitude)
            sw.longitude = min(sw.longitude, c.longitude)
            ne.latitude = max(ne.latitude, c.latitude)
            ne.longitude = max(ne.longitude, c.longitude)
        }
        let bounds = MLNCoordinateBounds(sw: sw, ne: ne)
        map.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 140, left: 40, bottom: 340, right: 80),
                                       animated: true, completionHandler: nil)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let camera: CameraController
        var images: [String: UIImage] = [:]
        var pitch: Double = 0
        var routeStyle: RouteStyle?
        var overlay = MapOverlayState()
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?

        init(camera: CameraController) {
            self.camera = camera
        }

        func applyPitch(_ map: MLNMapView) {
            let cam = map.camera
            cam.pitch = pitch
            map.setCamera(cam, animated: true)
        }

        func reinstallLayers(_ style: MLNStyle) {
            for id in ["fn-route-alt", "fn-route-glow", "fn-route-casing", "fn-route", "fn-next", "fn-puck"] {
                if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
            }
            for id in [RouteLayers.routeSource, RouteLayers.pointSource] {
                if let source = style.source(withIdentifier: id) { style.removeSource(source) }
            }
            if let routeStyle { RouteLayers.install(in: style, routeStyle: routeStyle) }
            RouteLayers.update(in: style, state: overlay)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            for (name, image) in images {
                style.setImage(image, forName: name)
            }
            reinstallLayers(style)
            applyPitch(mapView)
        }

        /// Страховка: стиль сослался на картинку, которой нет — отдаём нейтральную метку.
        func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            images[imageName] ?? images["blip.generic"]
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            // MapLibre сбрасывает трекинг в .none, когда пользователь двигает карту.
            if mode == .none, overlay.puck == nil {
                camera.userDidPan()
            }
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            // Жест пользователя во время ведения — отпускаем камеру.
            if overlay.puck != nil, reason.contains(.gesturePan) || reason.contains(.gesturePinch) {
                camera.userDidPan()
            }
        }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MLNMapView else { return }
            onLongPress?(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }
    }
}

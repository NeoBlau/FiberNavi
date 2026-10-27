import Foundation
import CoreLocation

/// Конфигурация из Info.plist. Значения можно переопределить без правки кода.
struct AppConfig {
    static let fallbackStyleURL = URL(string: "https://demotiles.maplibre.org/style.json")!
    /// Центр Москвы — стартовая позиция камеры до первого фикса GPS.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
    static let defaultZoom: Double = 11

    let mapStyleURL: URL

    init(info: [String: Any]) {
        if let raw = info["FNMapStyleURL"] as? String, let url = URL(string: raw), url.scheme != nil {
            mapStyleURL = url
        } else {
            mapStyleURL = Self.fallbackStyleURL
        }
    }

    static let current = AppConfig(info: Bundle.main.infoDictionary ?? [:])
}

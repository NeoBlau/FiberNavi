import Foundation
import CoreLocation

/// Конфигурация из Info.plist с переопределением в настройках (UserDefaults).
struct AppConfig {
    static let fallbackStyleURL = URL(string: "https://demotiles.maplibre.org/style.json")!
    /// Центр Москвы — стартовая позиция камеры до первого фикса GPS.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
    static let defaultZoom: Double = 11

    /// Ключи совпадают в Info.plist и UserDefaults.
    enum Key {
        static let mapStyle = "FNMapStyleURL"
        static let tiles = "FNTilesURL"
        static let routing = "FNValhallaURL"
        static let search = "FNPhotonURL"
    }

    let mapStyleURL: URL
    /// TileJSON своего сервера (`http://host:8080/moscow.json`). nil — OpenFreeMap.
    let tilesURL: URL?
    /// Valhalla (`http://host:8002`).
    let routingURL: URL?
    /// Photon (`http://host:2322`).
    let searchURL: URL?

    init(info: [String: Any], overrides: [String: Any] = [:]) {
        func url(_ key: String) -> URL? {
            let raw = (overrides[key] as? String) ?? (info[key] as? String) ?? ""
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme != nil, url.host != nil else {
                return nil
            }
            return url
        }
        mapStyleURL = url(Key.mapStyle) ?? Self.fallbackStyleURL
        tilesURL = url(Key.tiles)
        routingURL = url(Key.routing)
        searchURL = url(Key.search)
    }

    static var current: AppConfig {
        AppConfig(info: Bundle.main.infoDictionary ?? [:],
                  overrides: UserDefaults.standard.dictionaryRepresentation())
    }
}

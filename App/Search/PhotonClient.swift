import Foundation
import CoreLocation

struct Place: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Поиск адресов и мест через Photon (`/api`, `/reverse`).
struct PhotonClient {
    let baseURL: URL
    var session: URLSession = .shared
    /// Москва и область — поиск не уезжает в другие города.
    var bbox = "35.14,54.25,40.21,56.96"

    func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> [Place] {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "12"),
                     URLQueryItem(name: "bbox", value: bbox)]
        if let near {
            items += [URLQueryItem(name: "lat", value: String(near.latitude)),
                      URLQueryItem(name: "lon", value: String(near.longitude))]
        }
        return try await get("api", items)
    }

    func reverse(_ coordinate: CLLocationCoordinate2D) async throws -> Place? {
        try await get("reverse", [URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                                  URLQueryItem(name: "lon", value: String(coordinate.longitude))]).first
    }

    private func get(_ path: String, _ items: [URLQueryItem]) async throws -> [Place] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        let (data, _) = try await session.data(for: request)
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> [Place] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { feature in
            guard let geometry = feature["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double], coords.count >= 2 else { return nil }
            let p = feature["properties"] as? [String: Any] ?? [:]
            let street = p["street"] as? String
            let house = p["housenumber"] as? String
            let address = [street, house].compactMap { $0 }.joined(separator: ", ")
            let name = (p["name"] as? String) ?? (address.isEmpty ? "Точка на карте" : address)
            let locality = [p["district"] as? String, p["city"] as? String ?? p["county"] as? String]
                .compactMap { $0 }
            let subtitle = ([address == name ? nil : address] + locality.map { Optional($0) })
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let osm = "\(p["osm_type"] as? String ?? "X")\(p["osm_id"].map { "\($0)" } ?? "\(coords[0]),\(coords[1])")"
            return Place(id: osm, name: name, subtitle: subtitle, latitude: coords[1], longitude: coords[0])
        }
    }
}

/// Избранное (дом, работа) и история поиска.
@Observable
final class PlacesStore {
    private(set) var home: Place?
    private(set) var work: Place?
    private(set) var favorites: [Place] = []
    private(set) var history: [Place] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        home = load("fn.home")
        work = load("fn.work")
        favorites = load("fn.favorites") ?? []
        history = load("fn.history") ?? []
    }

    func setHome(_ place: Place?) { home = place; save(place, "fn.home") }
    func setWork(_ place: Place?) { work = place; save(place, "fn.work") }

    func toggleFavorite(_ place: Place) {
        if let i = favorites.firstIndex(where: { $0.id == place.id }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(place, at: 0)
        }
        save(favorites, "fn.favorites")
    }

    func isFavorite(_ place: Place) -> Bool { favorites.contains { $0.id == place.id } }

    func remember(_ place: Place) {
        history.removeAll { $0.id == place.id }
        history.insert(place, at: 0)
        history = Array(history.prefix(20))
        save(history, "fn.history")
    }

    func clearHistory() {
        history = []
        save(history, "fn.history")
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

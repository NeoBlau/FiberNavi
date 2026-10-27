import Foundation
import CoreLocation

protocol RoutingEngine {
    /// Основной маршрут первым, затем альтернативы.
    func routes(from origin: CLLocationCoordinate2D, heading: Double?, to destination: CLLocationCoordinate2D,
                mode: TravelMode, alternatives: Int) async throws -> [Route]
}

enum RoutingError: LocalizedError {
    case notConfigured
    case server(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Не задан адрес сервера маршрутов (Настройки → Сервер)."
        case .server(let message): "Сервер маршрутов: \(message)"
        case .noRoute: "Маршрут не найден."
        }
    }
}

/// Клиент Valhalla `/route` и `/trace_attributes` (ограничения скорости).
/// Тот же формат ответа отдаёт и Valhalla на устройстве (этап 7a).
struct ValhallaClient: RoutingEngine {
    let baseURL: URL
    var session: URLSession = .shared

    func routes(from origin: CLLocationCoordinate2D, heading: Double?, to destination: CLLocationCoordinate2D,
                mode: TravelMode, alternatives: Int) async throws -> [Route] {
        var start: [String: Any] = ["lat": origin.latitude, "lon": origin.longitude]
        if let heading {
            start["heading"] = Int(heading)
            start["heading_tolerance"] = 45
        }
        let body: [String: Any] = [
            "locations": [start, ["lat": destination.latitude, "lon": destination.longitude]],
            "costing": mode.rawValue,
            "alternates": alternatives,
            "units": "kilometers",
            "language": "en-US",
            "directions_options": ["units": "kilometers", "language": "en-US"],
        ]
        let data = try await post("route", body: body)
        var routes = try Self.parseRoutes(data)
        guard !routes.isEmpty else { throw RoutingError.noRoute }
        if mode == .auto {
            for i in routes.indices {
                routes[i].speedLimits = (try? await speedLimits(for: routes[i])) ?? []
            }
        }
        return routes
    }

    func speedLimits(for route: Route) async throws -> [SpeedLimitSpan] {
        let body: [String: Any] = [
            "encoded_polyline": Polyline.encode(route.coordinates),
            "shape_match": "edge_walk",
            "costing": "auto",
            "filters": ["attributes": ["edge.speed_limit", "edge.begin_shape_index", "edge.end_shape_index"],
                        "action": "include"],
        ]
        let data = try await post("trace_attributes", body: body)
        return Self.parseSpeedLimits(data, route: route)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw RoutingError.server(message ?? "HTTP \(http.statusCode)")
        }
        return data
    }

    // MARK: Parsing

    static func parseRoutes(_ data: Data) throws -> [Route] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var trips: [[String: Any]] = []
        if let trip = root["trip"] as? [String: Any] { trips.append(trip) }
        for alt in root["alternates"] as? [[String: Any]] ?? [] {
            if let trip = alt["trip"] as? [String: Any] { trips.append(trip) }
        }
        return trips.compactMap(parseTrip)
    }

    static func parseTrip(_ trip: [String: Any]) -> Route? {
        var coordinates: [CLLocationCoordinate2D] = []
        var raw: [(kind: ManeuverKind, instruction: String, streets: [String], begin: Int, length: Double,
                   time: Double, exit: Int?, lanes: [Lane])] = []
        var duration = 0.0

        for leg in trip["legs"] as? [[String: Any]] ?? [] {
            let offset = coordinates.isEmpty ? 0 : coordinates.count - 1
            var shape = Polyline.decode(leg["shape"] as? String ?? "")
            if !coordinates.isEmpty, !shape.isEmpty { shape.removeFirst() }
            coordinates += shape
            duration += (leg["summary"] as? [String: Any])?["time"] as? Double ?? 0
            for m in leg["maneuvers"] as? [[String: Any]] ?? [] {
                let lanes = (m["lanes"] as? [[String: Any]] ?? []).map {
                    // Поле `valid`/`active` бывает строкой или массивом в разных версиях — достаточно наличия.
                    Lane(directions: $0["directions"] as? [String] ?? [], isValid: $0["valid"] != nil || $0["active"] != nil)
                }
                raw.append((
                    kind: ManeuverKind(valhallaType: m["type"] as? Int ?? 0),
                    instruction: m["instruction"] as? String ?? "",
                    streets: m["street_names"] as? [String] ?? [],
                    begin: (m["begin_shape_index"] as? Int ?? 0) + offset,
                    length: (m["length"] as? Double ?? 0) * 1000,
                    time: m["time"] as? Double ?? 0,
                    exit: m["roundabout_exit_count"] as? Int,
                    lanes: lanes
                ))
            }
        }
        guard coordinates.count >= 2 else { return nil }

        let draft = Route(coordinates: coordinates, maneuvers: [], duration: duration)
        var maneuvers: [Maneuver] = []
        for (i, m) in raw.enumerated() {
            // Промежуточные «прибытия» на стыках ног пропускаем.
            if m.kind == .arrive, i != raw.count - 1 { continue }
            if m.kind == .depart, i != 0 { continue }
            let index = min(m.begin, coordinates.count - 1)
            maneuvers.append(Maneuver(id: maneuvers.count, kind: m.kind, instruction: m.instruction,
                                      streetNames: m.streets, beginShapeIndex: index,
                                      distanceFromStart: draft.cumulative[index], length: m.length,
                                      duration: m.time, roundaboutExit: m.exit, lanes: m.lanes))
        }
        return Route(coordinates: coordinates, maneuvers: maneuvers, duration: duration)
    }

    static func parseSpeedLimits(_ data: Data, route: Route) -> [SpeedLimitSpan] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let edges = root["edges"] as? [[String: Any]] else { return [] }
        let last = route.cumulative.count - 1
        var spans: [SpeedLimitSpan] = []
        for edge in edges {
            // 0 и 255 у Valhalla означают «нет данных / без ограничения».
            guard let limit = edge["speed_limit"] as? Double, limit > 0, limit < 255,
                  let b = edge["begin_shape_index"] as? Int, let e = edge["end_shape_index"] as? Int else { continue }
            let start = route.cumulative[min(max(b, 0), last)]
            let end = route.cumulative[min(max(e, 0), last)]
            if let prev = spans.last, prev.limit == limit, abs(prev.endDistance - start) < 1 {
                spans[spans.count - 1] = SpeedLimitSpan(startDistance: prev.startDistance, endDistance: end, limit: limit)
            } else {
                spans.append(SpeedLimitSpan(startDistance: start, endDistance: end, limit: limit))
            }
        }
        return spans
    }
}

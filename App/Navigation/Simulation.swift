import Foundation
import CoreLocation

/// Чтение треков GPX (trkpt и rtept).
enum GPXParser {
    static func parse(_ data: Data) -> [CLLocation] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [CLLocation] = []
        private var lat: Double?
        private var lon: Double?
        private var time: Date?
        private var text = ""
        private let iso = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if name == "trkpt" || name == "rtept" {
                lat = attributes["lat"].flatMap(Double.init)
                lon = attributes["lon"].flatMap(Double.init)
                time = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "time" {
                time = iso.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if (name == "trkpt" || name == "rtept"), let lat, let lon {
                points.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                         altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                                         timestamp: time ?? Date(timeIntervalSince1970: 0)))
                self.lat = nil
                self.lon = nil
            }
        }
    }
}

/// Генерирует фиксы GPS вдоль линии с заданной скоростью — «поездка» без выхода на улицу.
struct TrackSimulator {
    let coordinates: [CLLocationCoordinate2D]
    let cumulative: [Double]
    /// м/с
    var speed: Double
    private(set) var traveled = 0.0

    init(coordinates: [CLLocationCoordinate2D], speed: Double) {
        self.coordinates = coordinates
        self.speed = speed
        var acc: [Double] = [0]
        for i in 1..<max(coordinates.count, 1) {
            acc.append(acc[i - 1] + Geo.distance(coordinates[i - 1], coordinates[i]))
        }
        cumulative = acc
    }

    init(route: Route, speed: Double) {
        self.init(coordinates: route.coordinates, speed: speed)
    }

    var length: Double { cumulative.last ?? 0 }
    var isFinished: Bool { traveled >= length }

    /// Сдвиг на dt секунд, возвращает новый фикс.
    mutating func advance(by dt: TimeInterval, at date: Date = Date()) -> CLLocation? {
        guard coordinates.count >= 2 else { return nil }
        traveled = min(length, traveled + speed * dt)
        var i = 0
        while i < cumulative.count - 2, cumulative[i + 1] < traveled { i += 1 }
        let seg = cumulative[i + 1] - cumulative[i]
        let t = seg > 0 ? (traveled - cumulative[i]) / seg : 0
        let point = Geo.interpolate(coordinates[i], coordinates[i + 1], t)
        let course = Geo.bearing(coordinates[i], coordinates[i + 1])
        return CLLocation(coordinate: point, altitude: 150, horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: course, courseAccuracy: 5, speed: isFinished ? 0 : speed, speedAccuracy: 1,
                          timestamp: date)
    }
}

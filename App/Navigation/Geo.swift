import Foundation
import CoreLocation

enum Geo {
    static let earthRadius = 6_371_008.8

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Курс от a к b, градусы 0…360 (0 — север).
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180
        let lat1 = a.latitude * rad, lat2 = b.latitude * rad
        let dLon = (b.longitude - a.longitude) * rad
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizeDegrees(atan2(y, x) / rad)
    }

    static func normalizeDegrees(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Минимальная разница курсов, 0…180.
    static func headingDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalizeDegrees(a) - normalizeDegrees(b))
        return d > 180 ? 360 - d : d
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Проекция точки p на отрезок ab в локальной плоской системе (метры).
    /// Возвращает параметр t ∈ [0, 1] и расстояние от p до проекции.
    static func project(_ p: CLLocationCoordinate2D, onSegment a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> (t: Double, distance: Double) {
        let rad = Double.pi / 180
        let kx = cos(a.latitude * rad) * rad * earthRadius
        let ky = rad * earthRadius
        let bx = (b.longitude - a.longitude) * kx, by = (b.latitude - a.latitude) * ky
        let px = (p.longitude - a.longitude) * kx, py = (p.latitude - a.latitude) * ky
        let len2 = bx * bx + by * by
        let t = len2 > 0 ? max(0, min(1, (px * bx + py * by) / len2)) : 0
        let dx = px - bx * t, dy = py - by * t
        return (t, sqrt(dx * dx + dy * dy))
    }
}

/// Декодер Google Encoded Polyline с точностью 1e-6 (формат `shape` у Valhalla).
enum Polyline {
    static func decode(_ encoded: String, precision: Double = 1e6) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.unicodeScalars.startIndex
        let scalars = encoded.unicodeScalars
        var lat = 0, lon = 0

        func next() -> Int? {
            var result = 0, shift = 0
            while index < scalars.endIndex {
                let byte = Int(scalars[index].value) - 63
                index = scalars.index(after: index)
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while index < scalars.endIndex {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return coordinates
    }

    static func encode(_ coordinates: [CLLocationCoordinate2D], precision: Double = 1e6) -> String {
        var out = ""
        var prevLat = 0, prevLon = 0
        func emit(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                out.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))
                v >>= 5
            }
            out.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for c in coordinates {
            let lat = Int((c.latitude * precision).rounded())
            let lon = Int((c.longitude * precision).rounded())
            emit(lat - prevLat)
            emit(lon - prevLon)
            prevLat = lat
            prevLon = lon
        }
        return out
    }
}

import Foundation
import CoreLocation

/// Высота солнца над горизонтом (упрощённый алгоритм NOAA, точность ~0.5°).
enum SolarCalculator {
    static func elevation(at coordinate: CLLocationCoordinate2D, date: Date) -> Double {
        let rad = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = julianDay - 2451545.0

        let meanLongitude = normalize(280.460 + 0.9856474 * n)
        let meanAnomaly = normalize(357.528 + 0.9856003 * n) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))

        let gmst = normalize(280.46061837 + 360.98564736629 * n)
        let hourAngle = (gmst + coordinate.longitude) * rad - rightAscension
        let latitude = coordinate.latitude * rad

        let sinElevation = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        return asin(sinElevation) / rad
    }

    /// Ночь — солнце ниже гражданских сумерек (−6°).
    static func isNight(at coordinate: CLLocationCoordinate2D, date: Date) -> Bool {
        elevation(at: coordinate, date: date) < -6
    }

    private static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

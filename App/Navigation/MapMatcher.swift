import Foundation
import CoreLocation

/// Привязка GPS-точки к линии маршрута. Ищет сначала рядом с прошлым сегментом,
/// чтобы не «перепрыгивать» на параллельный участок (эстакады, развязки МКАД).
struct MapMatcher {
    struct Match: Equatable {
        let coordinate: CLLocationCoordinate2D
        let segmentIndex: Int
        /// Пройдено по маршруту, м.
        let distanceAlong: Double
        /// Боковое отклонение от маршрута, м.
        let offset: Double
        /// Курс маршрута в точке привязки.
        let routeBearing: Double

        static func == (a: Match, b: Match) -> Bool {
            a.segmentIndex == b.segmentIndex && a.distanceAlong == b.distanceAlong && a.offset == b.offset
        }
    }

    let route: Route
    private(set) var lastSegment = 0
    /// Сколько сегментов назад/вперёд смотреть при локальном поиске.
    var backWindow = 3
    var forwardWindow = 40
    /// Штраф (в метрах) за расхождение курса движения и курса сегмента на 90°.
    var headingPenalty = 25.0

    init(route: Route) {
        self.route = route
    }

    mutating func match(_ location: CLLocation) -> Match? {
        let count = route.coordinates.count
        guard count >= 2 else { return nil }
        let lo = max(0, lastSegment - backWindow)
        let hi = min(count - 2, lastSegment + forwardWindow)
        var best = bestMatch(location, in: lo...hi)
        // Далеко от ожидаемого места — ищем по всему маршруту (старт с середины, сильный дрейф GPS).
        if best == nil || best!.offset > 60 {
            if let global = bestMatch(location, in: 0...(count - 2)), global.offset < (best?.offset ?? .infinity) {
                best = global
            }
        }
        if let best { lastSegment = best.segmentIndex }
        return best
    }

    mutating func reset() { lastSegment = 0 }

    private func bestMatch(_ location: CLLocation, in range: ClosedRange<Int>) -> Match? {
        let p = location.coordinate
        let course = location.course >= 0 && location.speed > 2 ? location.course : nil
        var best: Match?
        var bestScore = Double.infinity
        for i in range {
            let a = route.coordinates[i], b = route.coordinates[i + 1]
            let (t, d) = Geo.project(p, onSegment: a, b)
            let segBearing = Geo.bearing(a, b)
            var score = d
            if let course {
                score += headingPenalty * Geo.headingDelta(course, segBearing) / 90
            }
            if score < bestScore {
                bestScore = score
                let along = route.cumulative[i] + (route.cumulative[i + 1] - route.cumulative[i]) * t
                best = Match(coordinate: Geo.interpolate(a, b, t), segmentIndex: i, distanceAlong: along,
                             offset: d, routeBearing: segBearing)
            }
        }
        return best
    }
}

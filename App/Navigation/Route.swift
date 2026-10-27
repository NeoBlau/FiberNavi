import Foundation
import CoreLocation

enum TravelMode: String, CaseIterable, Identifiable, Codable {
    case auto, pedestrian, bicycle
    var id: String { rawValue }
}

/// Тип манёвра, нормализованный из кодов Valhalla.
enum ManeuverKind: String, Codable {
    case depart, arrive, straight, slightLeft, slightRight, left, right, sharpLeft, sharpRight
    case uturn, keepLeft, keepRight, rampLeft, rampRight, exitLeft, exitRight, merge
    case roundaboutEnter, roundaboutExit, ferry

    var isTurn: Bool {
        switch self {
        case .depart, .arrive, .straight: false
        default: true
        }
    }

    /// Valhalla `maneuver.type` → вид манёвра.
    init(valhallaType: Int) {
        switch valhallaType {
        case 1, 2, 3: self = .depart
        case 4, 5, 6: self = .arrive
        case 7, 8, 17, 22: self = .straight
        case 9: self = .slightRight
        case 10: self = .right
        case 11: self = .sharpRight
        case 12, 13: self = .uturn
        case 14: self = .sharpLeft
        case 15: self = .left
        case 16: self = .slightLeft
        case 18: self = .rampRight
        case 19: self = .rampLeft
        case 20: self = .exitRight
        case 21: self = .exitLeft
        case 23: self = .keepRight
        case 24: self = .keepLeft
        case 25, 37, 38: self = .merge
        case 26: self = .roundaboutEnter
        case 27: self = .roundaboutExit
        case 28, 29: self = .ferry
        default: self = .straight
        }
    }

    var symbol: String {
        switch self {
        case .depart: "location.north.fill"
        case .arrive: "flag.checkered"
        case .straight: "arrow.up"
        case .slightLeft, .keepLeft: "arrow.up.left"
        case .slightRight, .keepRight: "arrow.up.right"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .uturn: "arrow.uturn.down"
        case .rampLeft, .exitLeft: "arrow.up.left"
        case .rampRight, .exitRight: "arrow.up.right"
        case .merge: "arrow.merge"
        case .roundaboutEnter, .roundaboutExit: "arrow.triangle.2.circlepath"
        case .ferry: "ferry.fill"
        }
    }
}

struct Lane: Codable, Equatable {
    var directions: [String]
    var isValid: Bool
}

struct Maneuver: Identifiable, Equatable {
    let id: Int
    let kind: ManeuverKind
    /// Текст инструкции от Valhalla (только на экран).
    let instruction: String
    let streetNames: [String]
    let beginShapeIndex: Int
    /// Расстояние от начала маршрута до точки манёвра, м.
    let distanceFromStart: Double
    /// Длина участка после манёвра до следующего, м.
    let length: Double
    let duration: Double
    let roundaboutExit: Int?
    let lanes: [Lane]
}

struct SpeedLimitSpan: Equatable {
    let startDistance: Double
    let endDistance: Double
    /// км/ч
    let limit: Double
}

struct Route: Identifiable, Equatable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    /// Накопленная длина до каждой вершины, м.
    let cumulative: [Double]
    let maneuvers: [Maneuver]
    let distance: Double
    let duration: Double
    var speedLimits: [SpeedLimitSpan] = []

    init(coordinates: [CLLocationCoordinate2D], maneuvers: [Maneuver], duration: Double, speedLimits: [SpeedLimitSpan] = []) {
        self.coordinates = coordinates
        var acc: [Double] = [0]
        acc.reserveCapacity(coordinates.count)
        for i in 1..<max(coordinates.count, 1) {
            acc.append(acc[i - 1] + Geo.distance(coordinates[i - 1], coordinates[i]))
        }
        cumulative = acc
        self.maneuvers = maneuvers
        distance = acc.last ?? 0
        self.duration = duration
        self.speedLimits = speedLimits
    }

    static func == (lhs: Route, rhs: Route) -> Bool { lhs.id == rhs.id }

    func speedLimit(at distanceAlong: Double) -> Double? {
        speedLimits.first { distanceAlong >= $0.startDistance && distanceAlong < $0.endDistance }?.limit
    }

    func coordinate(at distanceAlong: Double) -> CLLocationCoordinate2D {
        guard let last = coordinates.last else { return AppConfig.defaultCenter }
        guard distanceAlong > 0 else { return coordinates[0] }
        guard distanceAlong < distance else { return last }
        var lo = 0, hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= distanceAlong { lo = mid } else { hi = mid }
        }
        let seg = cumulative[hi] - cumulative[lo]
        let t = seg > 0 ? (distanceAlong - cumulative[lo]) / seg : 0
        return Geo.interpolate(coordinates[lo], coordinates[hi], t)
    }

    /// Курс маршрута в точке.
    func bearing(at distanceAlong: Double) -> Double {
        let a = coordinate(at: max(0, distanceAlong - 5))
        let b = coordinate(at: min(distance, distanceAlong + 5))
        return Geo.bearing(a, b)
    }
}

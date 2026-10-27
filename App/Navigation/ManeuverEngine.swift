import Foundation

/// Этапы объявления манёвра. Голос без чисел: far — «up ahead», near — «turn left», now — «now, left».
enum AnnouncementStage: Int, Comparable, CaseIterable, Codable {
    case far, near, now
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct NavigationProgress: Equatable {
    var nextManeuver: Maneuver?
    var maneuverAfter: Maneuver?
    var distanceToManeuver: Double
    var remainingDistance: Double
    var remainingTime: TimeInterval
    var distanceAlong: Double
}

/// Считает прогресс по маршруту и решает, когда объявлять манёвр.
struct ManeuverEngine {
    struct Announcement: Equatable {
        let maneuver: Maneuver
        let stage: AnnouncementStage
        let distance: Double
    }

    struct Thresholds {
        /// «Далеко» на скоростной дороге / в городе, м.
        var farHighway = 1000.0
        var farCity = 500.0
        /// «Скоро»: не ближе этого и не меньше 12 секунд хода.
        var nearMinimum = 200.0
        var nearSeconds = 12.0
        /// «Сейчас»: не ближе этого и не меньше 4 секунд хода.
        var nowMinimum = 40.0
        var nowSeconds = 4.0
        /// Скорость, с которой считаем дорогу скоростной, м/с (≈ 70 км/ч).
        var highwaySpeed = 19.4
        /// После манёвра проезжаем столько метров, прежде чем переключиться на следующий.
        var passMargin = 10.0
    }

    let route: Route
    var thresholds = Thresholds()
    private var announced: [Int: AnnouncementStage] = [:]

    init(route: Route) {
        self.route = route
    }

    func progress(distanceAlong: Double) -> NavigationProgress {
        let upcoming = route.maneuvers.filter { $0.kind != .depart && $0.distanceFromStart >= distanceAlong - thresholds.passMargin }
        let next = upcoming.first
        let remaining = max(0, route.distance - distanceAlong)
        let fraction = route.distance > 0 ? remaining / route.distance : 0
        return NavigationProgress(
            nextManeuver: next,
            maneuverAfter: upcoming.dropFirst().first,
            distanceToManeuver: max(0, (next?.distanceFromStart ?? route.distance) - distanceAlong),
            remainingDistance: remaining,
            remainingTime: route.duration * fraction,
            distanceAlong: distanceAlong
        )
    }

    /// Граница этапа в метрах при текущей скорости (м/с).
    func threshold(for stage: AnnouncementStage, speed: Double) -> Double {
        let v = max(0, speed)
        switch stage {
        case .far: return v >= thresholds.highwaySpeed ? thresholds.farHighway : thresholds.farCity
        case .near: return max(thresholds.nearMinimum, v * thresholds.nearSeconds)
        case .now: return max(thresholds.nowMinimum, v * thresholds.nowSeconds)
        }
    }

    /// Возвращает объявление, если пора. Каждый этап манёвра звучит не больше одного раза;
    /// если въехали сразу в ближний этап, дальние пропускаются.
    mutating func announcement(for progress: NavigationProgress, speed: Double) -> Announcement? {
        guard let maneuver = progress.nextManeuver else { return nil }
        let d = progress.distanceToManeuver
        var due: AnnouncementStage?
        for stage in AnnouncementStage.allCases.reversed() where d <= threshold(for: stage, speed: speed) {
            due = stage
            break
        }
        guard let due else { return nil }
        if let done = announced[maneuver.id], done >= due { return nil }
        // «Далеко» не объявляем, если до манёвра почти столько же, сколько до «скоро»: будет дубль.
        if due == .far, d - threshold(for: .near, speed: speed) < 100 { return nil }
        announced[maneuver.id] = due
        return Announcement(maneuver: maneuver, stage: due, distance: d)
    }

    mutating func resetAnnouncements() { announced.removeAll() }
}

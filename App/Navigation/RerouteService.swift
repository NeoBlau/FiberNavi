import Foundation

/// Решает, когда перестраивать маршрут: отклонение держится дольше задержки, GPS достаточно точный,
/// с прошлого перестроения прошёл кулдаун.
struct RerouteService {
    struct Settings: Equatable {
        /// Порог отклонения от линии маршрута, м.
        var offRouteDistance = 40.0
        /// Сколько секунд отклонение должно держаться.
        var delay = 4.0
        /// Точки с худшей точностью игнорируются, м.
        var maxAccuracy = 50.0
        /// Минимум между перестроениями, с.
        var cooldown = 10.0
    }

    var settings = Settings()
    private var offSince: Date?
    private var lastReroute: Date?

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    var isOffRoute: Bool { offSince != nil }

    /// true — пора запрашивать новый маршрут.
    mutating func update(offset: Double, accuracy: Double, at now: Date) -> Bool {
        guard accuracy >= 0, accuracy <= settings.maxAccuracy else { return false }
        guard offset > settings.offRouteDistance else {
            offSince = nil
            return false
        }
        let since = offSince ?? now
        offSince = since
        guard now.timeIntervalSince(since) >= settings.delay else { return false }
        if let lastReroute, now.timeIntervalSince(lastReroute) < settings.cooldown { return false }
        lastReroute = now
        offSince = nil
        return true
    }

    mutating func reset() {
        offSince = nil
    }
}

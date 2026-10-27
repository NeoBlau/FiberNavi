import Foundation

/// События навигации. По ним VoiceDirector выбирает реплики, HUD — подсказки.
enum GuidanceEvent: Equatable {
    case routeStarted
    case maneuver(kind: ManeuverKind, stage: AnnouncementStage, roundaboutExit: Int?)
    case reroute
    case arrived
    case speeding(limit: Double)
    case speedCamera
    case trafficJam
    case longStraight
    case nightDriving
    case longStop
    case badGPS

    /// Ключ события в voice_manifest.json.
    var voiceKey: String {
        switch self {
        case .routeStarted: "route_start"
        case .maneuver(let kind, let stage, _): "\(kind.voiceKey)_\(stage.voiceSuffix)"
        case .reroute: "reroute"
        case .arrived: "arrived"
        case .speeding: "speeding"
        case .speedCamera: "speed_camera"
        case .trafficJam: "traffic_jam"
        case .longStraight: "long_straight"
        case .nightDriving: "night_driving"
        case .longStop: "long_stop"
        case .badGPS: "bad_gps"
        }
    }

    /// Приоритет очереди: манёвр > перестроение > предупреждения > болтовня.
    var priority: VoicePriority {
        switch self {
        case .maneuver, .arrived: .instruction
        case .reroute: .reroute
        case .speeding, .speedCamera, .badGPS: .warning
        case .routeStarted, .trafficJam, .longStraight, .nightDriving, .longStop: .chatter
        }
    }
}

enum VoicePriority: Int, Comparable {
    case chatter = 0, warning = 1, reroute = 2, instruction = 3
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension ManeuverKind {
    /// Базовый ключ манёвра для голоса.
    var voiceKey: String {
        switch self {
        case .left, .sharpLeft: "turn_left"
        case .right, .sharpRight: "turn_right"
        case .slightLeft, .keepLeft, .rampLeft, .exitLeft: "keep_left"
        case .slightRight, .keepRight, .rampRight, .exitRight: "keep_right"
        case .uturn: "uturn"
        case .roundaboutEnter, .roundaboutExit: "roundabout"
        case .merge: "merge"
        case .straight, .depart, .ferry: "straight"
        case .arrive: "arrive"
        }
    }
}

extension AnnouncementStage {
    var voiceSuffix: String {
        switch self {
        case .far: "far"
        case .near: "near"
        case .now: "now"
        }
    }
}

/// Детекторы событий «не про манёвры»: превышение, пробка, длинная прямая, стоянка, плохой GPS.
struct DrivingMonitor {
    struct Settings {
        var speedingTolerance = 10.0          // км/ч сверх лимита
        var speedingRepeat: TimeInterval = 60
        var jamMinLimit = 40.0                // км/ч: на дорогах медленнее пробку не считаем
        var jamSpeed = 10.0                   // км/ч
        var jamDuration: TimeInterval = 120
        var longStraightDistance = 5000.0     // м до следующего манёвра
        var longStopDuration: TimeInterval = 300
        var badAccuracy = 50.0                // м
        var badGPSDuration: TimeInterval = 15
    }

    var settings = Settings()
    private var lastSpeeding: Date?
    private var slowSince: Date?
    private var jamAnnounced = false
    private var stopSince: Date?
    private var stopAnnounced = false
    private var badSince: Date?
    private var badAnnounced = false
    private var straightAnnouncedFor: Int?

    /// speed — м/с, limit — км/ч.
    mutating func update(speed: Double, accuracy: Double, limit: Double?, distanceToManeuver: Double,
                         maneuverID: Int?, now: Date) -> [GuidanceEvent] {
        var events: [GuidanceEvent] = []
        let kmh = max(0, speed) * 3.6

        if let limit, kmh > limit + settings.speedingTolerance {
            if lastSpeeding.map({ now.timeIntervalSince($0) >= settings.speedingRepeat }) ?? true {
                lastSpeeding = now
                events.append(.speeding(limit: limit))
            }
        }

        if let limit, limit >= settings.jamMinLimit, kmh < settings.jamSpeed, kmh > 0.5 || slowSince != nil {
            let since = slowSince ?? now
            slowSince = since
            if !jamAnnounced, now.timeIntervalSince(since) >= settings.jamDuration {
                jamAnnounced = true
                events.append(.trafficJam)
            }
        } else if kmh >= settings.jamSpeed * 2 {
            slowSince = nil
            jamAnnounced = false
        }

        if kmh < 1 {
            let since = stopSince ?? now
            stopSince = since
            if !stopAnnounced, now.timeIntervalSince(since) >= settings.longStopDuration {
                stopAnnounced = true
                events.append(.longStop)
            }
        } else {
            stopSince = nil
            stopAnnounced = false
        }

        if accuracy < 0 || accuracy > settings.badAccuracy {
            let since = badSince ?? now
            badSince = since
            if !badAnnounced, now.timeIntervalSince(since) >= settings.badGPSDuration {
                badAnnounced = true
                events.append(.badGPS)
            }
        } else {
            badSince = nil
            badAnnounced = false
        }

        if let maneuverID, distanceToManeuver >= settings.longStraightDistance, straightAnnouncedFor != maneuverID {
            straightAnnouncedFor = maneuverID
            events.append(.longStraight)
        }
        return events
    }
}

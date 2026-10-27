import Foundation
import Observation

/// voice_manifest.json персонажа. Генерирует tools/voice_tagger.
struct VoiceManifest: Codable {
    struct Line: Codable, Equatable {
        var id: String
        var file: String
        var text: String?
        /// Ключи событий: `turn_left_near`, `turn_left`, `arrived`, `speeding`, `idle_chatter`, `confirm`…
        var events: [String]
        var mood: String?
        var weight: Double?
        /// 0 — чисто, 1 — умеренно, 2 — жёстко.
        var explicit: Int?
        var conditions: Conditions?
    }

    struct Conditions: Codable, Equatable {
        /// "day" или "night".
        var time: String?
        var minSpeed: Double?
        var maxSpeed: Double?
        /// Сколько раз за поездку максимум.
        var maxPlays: Int?

        enum CodingKeys: String, CodingKey {
            case time
            case minSpeed = "min_speed"
            case maxSpeed = "max_speed"
            case maxPlays = "max_plays"
        }
    }

    struct WordTake: Codable, Equatable {
        var file: String
        /// Чистота дубля 0…1 (громкость, фон, паузы по краям).
        var score: Double
        var rejected: Bool?
    }

    var character: String
    var version: Int?
    var lines: [Line]
    /// Нарезка слов: "left", "right", "turn", "now", "up_ahead", "here"…
    var words: [String: [WordTake]]?
    /// Переопределения шаблонов склейки: событие → варианты последовательностей слов.
    var templates: [String: [[String]]]?
}

/// Настройки голоса (сохраняются).
@Observable
final class VoiceSettings {
    enum Chatter: String, CaseIterable, Identifiable {
        case rare, normal, often
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rare: "Редко"
            case .normal: "Обычно"
            case .often: "Часто"
            }
        }
        /// Минимум между репликами болтовни.
        var interval: TimeInterval {
            switch self {
            case .rare: 600
            case .normal: 300
            case .often: 120
            }
        }
    }

    enum Profanity: String, CaseIterable, Identifiable {
        case off, moderate, strict
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Выкл"
            case .moderate: "Умеренно"
            case .strict: "Жёстко"
            }
        }
        /// Максимально допустимый уровень `explicit`.
        var maxLevel: Int {
            switch self {
            case .off: 2
            case .moderate: 1
            case .strict: 0
            }
        }
    }

    var characterID: String { didSet { defaults.set(characterID, forKey: "fn.voice.character") } }
    var instructionsOnly: Bool { didSet { defaults.set(instructionsOnly, forKey: "fn.voice.instructionsOnly") } }
    var chatter: Chatter { didSet { defaults.set(chatter.rawValue, forKey: "fn.voice.chatter") } }
    var profanity: Profanity { didSet { defaults.set(profanity.rawValue, forKey: "fn.voice.profanity") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        characterID = defaults.string(forKey: "fn.voice.character") ?? ""
        instructionsOnly = defaults.bool(forKey: "fn.voice.instructionsOnly")
        chatter = defaults.string(forKey: "fn.voice.chatter").flatMap(Chatter.init(rawValue:)) ?? .normal
        profanity = defaults.string(forKey: "fn.voice.profanity").flatMap(Profanity.init(rawValue:)) ?? .moderate
    }
}

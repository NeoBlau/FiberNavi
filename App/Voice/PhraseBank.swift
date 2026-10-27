import Foundation

/// Что произнести: целая реплика (слой 1), склейка слов (слой 2) или фолбэк без слов (слой 3).
struct VoiceUtterance: Equatable {
    enum Source: Equatable {
        case line(id: String)
        case stitched(words: [String])
        /// UI-звук темы + мигание стрелки + короткое «подтверждение» героя (если есть).
        case fallback(confirmLineID: String?)
    }

    let eventKey: String
    let priority: VoicePriority
    let source: Source
    /// Файлы по порядку: одна реплика или слова для склейки.
    let files: [URL]
}

/// Банк реплик персонажа: событие → варианты → вес, условия, антиповтор.
final class PhraseBank {
    struct Context {
        var now: Date
        var isNight: Bool
        /// км/ч
        var speed: Double
        var profanity: VoiceSettings.Profanity
    }

    /// Одна реплика не чаще раза за 20 минут.
    var antiRepeat: TimeInterval = 20 * 60

    let manifest: VoiceManifest
    let baseURL: URL
    private var lastPlayed: [String: Date] = [:]
    private var playCount: [String: Int] = [:]
    private var lastWordTake: [String: String] = [:]
    private var rng: SplitMix64

    /// Шаблоны склейки по умолчанию (английский, как в играх). Первые варианты — предпочтительные.
    static let defaultTemplates: [String: [[String]]] = [
        "turn_left_far": [["up_ahead", "turn", "left"], ["up_ahead", "left"]],
        "turn_left_near": [["turn", "left"], ["go", "left"], ["left"]],
        "turn_left_now": [["now", "left"], ["turn", "left", "now"], ["left"]],
        "turn_right_far": [["up_ahead", "turn", "right"], ["up_ahead", "right"]],
        "turn_right_near": [["turn", "right"], ["go", "right"], ["right"]],
        "turn_right_now": [["now", "right"], ["turn", "right", "now"], ["right"]],
        "keep_left_far": [["up_ahead", "keep", "left"], ["up_ahead", "stay", "left"]],
        "keep_left_near": [["keep", "left"], ["stay", "left"]],
        "keep_left_now": [["keep", "left"], ["left"]],
        "keep_right_far": [["up_ahead", "keep", "right"], ["up_ahead", "stay", "right"]],
        "keep_right_near": [["keep", "right"], ["stay", "right"]],
        "keep_right_now": [["keep", "right"], ["right"]],
        "straight_near": [["keep", "straight"], ["go", "straight"], ["straight"]],
        "straight_now": [["straight"]],
        "uturn_near": [["turn", "around"], ["go", "back"]],
        "uturn_now": [["turn", "around"], ["back"]],
        "arrived": [["we're", "here"], ["here"]],
        "speeding": [["slow", "down"]],
        "merge_near": [["merge"]],
    ]

    init(manifest: VoiceManifest, baseURL: URL, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.manifest = manifest
        self.baseURL = baseURL
        rng = SplitMix64(seed: seed)
    }

    static func load(from url: URL) throws -> PhraseBank {
        let manifest = try JSONDecoder().decode(VoiceManifest.self, from: Data(contentsOf: url))
        return PhraseBank(manifest: manifest, baseURL: url.deletingLastPathComponent())
    }

    /// Сбросить счётчики «сколько раз за поездку».
    func resetTrip() { playCount.removeAll() }

    func utterance(for event: GuidanceEvent, context: Context) -> VoiceUtterance? {
        let key = event.voiceKey
        let isInstruction = event.priority >= .reroute
        for candidateKey in Self.fallbackKeys(for: key) {
            if let line = pickLine(for: candidateKey, context: context) {
                return markPlayed(line, event: key, priority: event.priority, context: context)
            }
        }
        // Инструкциям разрешаем повтор реплики, если свежих нет.
        if isInstruction {
            for candidateKey in Self.fallbackKeys(for: key) {
                if let line = pickLine(for: candidateKey, context: context, allowRecent: true) {
                    return markPlayed(line, event: key, priority: event.priority, context: context)
                }
            }
        }
        if let stitched = stitch(key) {
            return VoiceUtterance(eventKey: key, priority: event.priority, source: .stitched(words: stitched.words),
                                  files: stitched.files)
        }
        guard isInstruction else { return nil }
        let confirm = pickLine(for: "confirm", context: context, allowRecent: true)
        if let confirm { lastPlayed[confirm.id] = context.now }
        return VoiceUtterance(eventKey: key, priority: event.priority, source: .fallback(confirmLineID: confirm?.id),
                              files: confirm.map { [baseURL.appendingPathComponent($0.file)] } ?? [])
    }

    /// `turn_left_near` → `turn_left_near`, `turn_left`.
    static func fallbackKeys(for key: String) -> [String] {
        for suffix in ["_far", "_near", "_now"] where key.hasSuffix(suffix) {
            return [key, String(key.dropLast(suffix.count))]
        }
        return [key]
    }

    private func pickLine(for key: String, context: Context, allowRecent: Bool = false) -> VoiceManifest.Line? {
        let candidates = manifest.lines.filter { line in
            guard line.events.contains(key) else { return false }
            if (line.explicit ?? 0) > context.profanity.maxLevel { return false }
            if let c = line.conditions {
                if let time = c.time, (time == "night") != context.isNight { return false }
                if let min = c.minSpeed, context.speed < min { return false }
                if let max = c.maxSpeed, context.speed > max { return false }
                if let maxPlays = c.maxPlays, playCount[line.id, default: 0] >= maxPlays { return false }
            }
            if !allowRecent, let last = lastPlayed[line.id], context.now.timeIntervalSince(last) < antiRepeat {
                return false
            }
            return true
        }
        guard !candidates.isEmpty else { return nil }
        // Без allowRecent свежих нет — пусто; с allowRecent берём самую давнюю.
        if allowRecent {
            return candidates.min { (lastPlayed[$0.id] ?? .distantPast) < (lastPlayed[$1.id] ?? .distantPast) }
        }
        return weightedPick(candidates)
    }

    private func weightedPick(_ lines: [VoiceManifest.Line]) -> VoiceManifest.Line {
        let total = lines.reduce(0) { $0 + max(0.01, $1.weight ?? 1) }
        var roll = Double.random(in: 0..<total, using: &rng)
        for line in lines {
            roll -= max(0.01, line.weight ?? 1)
            if roll < 0 { return line }
        }
        return lines[lines.count - 1]
    }

    private func markPlayed(_ line: VoiceManifest.Line, event: String, priority: VoicePriority, context: Context) -> VoiceUtterance {
        lastPlayed[line.id] = context.now
        playCount[line.id, default: 0] += 1
        return VoiceUtterance(eventKey: event, priority: priority, source: .line(id: line.id),
                              files: [baseURL.appendingPathComponent(line.file)])
    }

    /// Слой 2: склеить инструкцию из лучших дублей слов. Берём первый шаблон, для которого есть все слова.
    private func stitch(_ key: String) -> (words: [String], files: [URL])? {
        let templates = manifest.templates?[key] ?? Self.defaultTemplates[key] ?? []
        guard let words = manifest.words else { return nil }
        for template in templates {
            var files: [URL] = []
            for word in template {
                guard let take = bestTake(word, in: words) else { files = []; break }
                files.append(baseURL.appendingPathComponent(take.file))
            }
            if files.count == template.count, !files.isEmpty {
                return (template, files)
            }
        }
        return nil
    }

    /// Лучший дубль, но не тот же, что в прошлый раз, если есть почти такой же хороший.
    private func bestTake(_ word: String, in words: [String: [VoiceManifest.WordTake]]) -> VoiceManifest.WordTake? {
        let takes = (words[word] ?? []).filter { $0.rejected != true }.sorted { $0.score > $1.score }
        guard let best = takes.first else { return nil }
        let pick: VoiceManifest.WordTake
        if takes.count > 1, lastWordTake[word] == best.file, takes[1].score >= best.score - 0.1 {
            pick = takes[1]
        } else {
            pick = best
        }
        lastWordTake[word] = pick.file
        return pick
    }
}

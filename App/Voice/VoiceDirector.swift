import AVFoundation
import Observation
import os

/// Воспроизведение. Протокол — чтобы проверять очередь в тестах без звука.
protocol VoicePlayer: AnyObject {
    func play(_ utterance: VoiceUtterance, completion: @escaping () -> Void)
    func stop()
}

/// Очередь реплик. Манёвр > перестроение > предупреждения > болтовня.
/// Реплика героя никогда не перебивает инструкцию и не накладывается на неё;
/// инструкция может оборвать болтовню.
@Observable
final class VoiceDirector {
    private(set) var current: VoiceUtterance?
    private(set) var queue: [VoiceUtterance] = []
    /// Журнал для отладки и UI-теста GPX-прогона.
    private(set) var log: [String] = []
    /// Последний фолбэк без слов: HUD мигает стрелкой.
    private(set) var lastFallbackAt: Date?

    var bank: PhraseBank?
    var settings: VoiceSettings
    var isNight: () -> Bool = { false }
    var currentSpeed: () -> Double = { 0 }
    /// UI-звук слоя 3 (ui.waypoint из пака темы).
    var playFallbackSound: () -> Void = {}
    var now: () -> Date = Date.init

    private let player: VoicePlayer
    private var lastChatter: Date?
    private let logger = Logger(subsystem: "local.fibernavi", category: "voice")

    init(player: VoicePlayer, settings: VoiceSettings) {
        self.player = player
        self.settings = settings
    }

    func handle(_ event: GuidanceEvent) {
        if event == .routeStarted { bank?.resetTrip() }
        let priority = event.priority
        if priority == .chatter {
            if settings.instructionsOnly { return }
            if let lastChatter, now().timeIntervalSince(lastChatter) < settings.chatter.interval, event != .routeStarted {
                return
            }
        }
        // Болтовня не ждёт в очереди и не встаёт поверх чего-либо.
        if priority == .chatter, current != nil || !queue.isEmpty { return }

        let context = PhraseBank.Context(now: now(), isNight: isNight(), speed: currentSpeed() * 3.6,
                                         profanity: settings.profanity)
        guard let utterance = bank?.utterance(for: event, context: context) ?? fallbackWithoutBank(event) else { return }
        if priority == .chatter { lastChatter = now() }
        enqueue(utterance)
    }

    /// Без пака голоса инструкции всё равно сопровождаются UI-звуком и миганием (слой 3).
    private func fallbackWithoutBank(_ event: GuidanceEvent) -> VoiceUtterance? {
        guard bank == nil, event.priority >= .reroute else { return nil }
        return VoiceUtterance(eventKey: event.voiceKey, priority: event.priority, source: .fallback(confirmLineID: nil), files: [])
    }

    private func enqueue(_ utterance: VoiceUtterance) {
        if let current {
            if utterance.priority == .instruction, current.priority == .chatter {
                logger.debug("Cut chatter for instruction")
                player.stop()
                self.current = nil
            } else {
                // Устаревшие объявления того же типа заменяем свежим.
                queue.removeAll { $0.priority == utterance.priority && utterance.priority == .instruction }
                queue.append(utterance)
                queue.sort { $0.priority > $1.priority }
                return
            }
        }
        start(utterance)
    }

    private func start(_ utterance: VoiceUtterance) {
        current = utterance
        log.append("\(utterance.priority) \(utterance.eventKey) \(describe(utterance.source))")
        if case .fallback = utterance.source {
            lastFallbackAt = now()
            playFallbackSound()
            if utterance.files.isEmpty {
                finish()
                return
            }
        }
        player.play(utterance) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        current = nil
        if !queue.isEmpty {
            start(queue.removeFirst())
        }
    }

    func stopAll() {
        queue.removeAll()
        player.stop()
        current = nil
    }

    private func describe(_ source: VoiceUtterance.Source) -> String {
        switch source {
        case .line(let id): "line:\(id)"
        case .stitched(let words): "words:\(words.joined(separator: "+"))"
        case .fallback(let id): "fallback:\(id ?? "-")"
        }
    }
}

/// Реальный плеер на AVAudioEngine: одна реплика или склейка слов, приглушение музыки на время звука.
final class EngineVoicePlayer: VoicePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var generation = 0
    private let logger = Logger(subsystem: "local.fibernavi", category: "voice")

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: PhraseStitcher.format)
    }

    func play(_ utterance: VoiceUtterance, completion: @escaping () -> Void) {
        let samples: [Float]
        do {
            let parts = try utterance.files.map(PhraseStitcher.loadSamples)
            switch utterance.source {
            case .stitched: samples = PhraseStitcher.process(parts)
            default: samples = PhraseStitcher.normalize(parts.flatMap { $0 })
            }
        } catch {
            logger.warning("Voice load failed: \(error.localizedDescription, privacy: .public)")
            completion()
            return
        }
        guard !samples.isEmpty, let buffer = PhraseStitcher.buffer(from: samples) else {
            completion()
            return
        }
        AudioSessionController.shared.activateForShortSound()
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            logger.warning("Audio engine: \(error.localizedDescription, privacy: .public)")
            completion()
            return
        }
        generation += 1
        let token = generation
        node.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                AudioSessionController.shared.release()
                completion()
            }
        }
        node.play()
    }

    func stop() {
        generation += 1
        node.stop()
    }
}

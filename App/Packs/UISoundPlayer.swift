import AVFoundation
import AudioToolbox
import os

/// Звуки интерфейса темы (`ui.*`). Без файла в паке играет короткий системный щелчок.
final class UISoundPlayer {
    private var players: [String: AVAudioPlayer] = [:]
    private let log = Logger(subsystem: "local.fibernavi", category: "sound")

    func play(_ key: String, from pack: UserPack) {
        guard let url = pack.url(for: key) else {
            AudioServicesPlaySystemSound(1104)
            return
        }
        do {
            let player: AVAudioPlayer
            if let cached = players[url.path] {
                player = cached
            } else {
                player = try AVAudioPlayer(contentsOf: url)
                players[url.path] = player
            }
            AudioSessionController.shared.activateForShortSound()
            player.currentTime = 0
            player.play()
        } catch {
            log.warning("Cannot play \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            AudioServicesPlaySystemSound(1104)
        }
    }
}

/// Общая аудиосессия: смешивание с музыкой пользователя и приглушение (ducking) на время звука.
final class AudioSessionController {
    static let shared = AudioSessionController()
    private let log = Logger(subsystem: "local.fibernavi", category: "audio")

    func activateForShortSound() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            log.warning("Audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Вернуть громкость музыке после реплики.
    func release() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

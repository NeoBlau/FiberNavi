import UIKit
import os

/// manifest.json пользовательского пака (образец: Assets/UserPacks/manifest.example.json).
struct PackManifest: Decodable {
    struct Voice: Decodable {
        var characters: [String: String]?
    }

    /// Версию не читаем: pack_tool пишет строку, старый образец — число.
    var theme: String?
    var map: [String: String]?
    var hud: [String: String]?
    var blips: [String: String]?
    var fonts: [String: String]?
    var sounds: [String: String]?
    var voice: Voice?

    /// Все ключи ассетов в одном словаре. Служебные ключи `_…` отбрасываются.
    var files: [String: String] {
        var out: [String: String] = [:]
        for group in [map, hud, blips, fonts, sounds] {
            for (key, path) in group ?? [:] where !key.hasPrefix("_") {
                out[key] = path
            }
        }
        return out
    }
}

/// Пак ассетов темы. Если файла нет, вызывающий код получает nil и подставляет заглушку,
/// а в debug-лог один раз пишется предупреждение.
final class UserPack {
    let theme: ThemeID
    let root: URL?
    let manifest: PackManifest?

    private let log = Logger(subsystem: "local.fibernavi", category: "packs")
    private var warned = Set<String>()
    private var imageCache: [String: UIImage] = [:]

    /// Форматы, которые iOS не открывает напрямую. pack_tool кладёт рядом сконвертированные копии.
    private static let convertedAlternatives: [String: [String]] = [
        "svg": ["png"],
        "dds": ["png"],
        "ogg": ["m4a", "caf", "wav"],
        "awc": ["wav", "m4a"],
    ]

    init(theme: ThemeID, root: URL?) {
        self.theme = theme
        self.root = root
        if let root, let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) {
            do {
                manifest = try JSONDecoder().decode(PackManifest.self, from: data)
            } catch {
                manifest = nil
                log.warning("Broken manifest.json for \(theme.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            manifest = nil
            log.warning("No user pack for theme \(theme.rawValue, privacy: .public), using stubs")
        }
    }

    /// Ищет пак сначала в Documents/UserPacks (импорт через «Файлы»), затем в бандле.
    static func load(_ theme: ThemeID, fileManager: FileManager = .default) -> UserPack {
        UserPack(theme: theme, root: locate(theme, fileManager: fileManager))
    }

    static func locate(_ theme: ThemeID, fileManager: FileManager = .default) -> URL? {
        var candidates: [URL] = []
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(docs.appendingPathComponent("UserPacks/\(theme.rawValue)", isDirectory: true))
        }
        if let bundled = Bundle.main.resourceURL {
            candidates.append(bundled.appendingPathComponent("UserPacks/\(theme.rawValue)", isDirectory: true))
        }
        return candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }

    var isInstalled: Bool { manifest != nil }

    /// Ключи из манифеста, файлов для которых нет на диске.
    var missingKeys: [String] {
        guard let manifest else { return [] }
        return manifest.files.keys.filter { url(for: $0, warn: false) == nil }.sorted()
    }

    func url(for key: String) -> URL? {
        url(for: key, warn: true)
    }

    private func url(for key: String, warn: Bool) -> URL? {
        guard let root, let relative = manifest?.files[key] else {
            if warn { warnOnce(key, "not in manifest") }
            return nil
        }
        let direct = root.appendingPathComponent(relative)
        let fm = FileManager.default
        let ext = direct.pathExtension.lowercased()
        if Self.convertedAlternatives[ext] == nil, fm.fileExists(atPath: direct.path) {
            return direct
        }
        for alt in Self.convertedAlternatives[ext] ?? [] {
            let candidate = direct.deletingPathExtension().appendingPathExtension(alt)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        if warn {
            let reason = Self.convertedAlternatives[ext] != nil ? "needs conversion (run tools/pack_tool)" : "file missing"
            warnOnce(key, "\(relative): \(reason)")
        }
        return nil
    }

    func image(_ key: String) -> UIImage? {
        if let cached = imageCache[key] { return cached }
        guard let url = url(for: key), let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[key] = image
        return image
    }

    func voiceManifestURL(character: String) -> URL? {
        guard let root, let relative = manifest?.voice?.characters?[character] else { return nil }
        let url = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func warnOnce(_ key: String, _ reason: String) {
        guard warned.insert(key).inserted else { return }
        log.debug("[\(self.theme.rawValue, privacy: .public)] \(key, privacy: .public) → stub (\(reason, privacy: .public))")
    }
}

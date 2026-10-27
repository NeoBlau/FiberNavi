import Foundation
import os

enum StyleVariant: String {
    case day, night
}

/// Готовит style JSON темы к загрузке: берёт сгенерированный стиль из бандла
/// и, если задан свой сервер тайлов, подменяет источник.
enum StyleCompiler {
    private static let log = Logger(subsystem: "local.fibernavi", category: "style")

    static func styleURL(theme: ThemeID, variant: StyleVariant, tilesURL: URL?) -> URL {
        let name = "\(theme.rawValue).\(variant.rawValue)"
        guard let bundled = Bundle.main.url(forResource: name, withExtension: "json") else {
            log.error("Missing bundled style \(name, privacy: .public)")
            return AppConfig.fallbackStyleURL
        }
        guard let tilesURL else { return bundled }
        do {
            let data = try Data(contentsOf: bundled)
            let patched = try patch(styleData: data, tilesURL: tilesURL)
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("styles", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("\(name).json")
            try patched.write(to: out, options: .atomic)
            return out
        } catch {
            log.error("Style patch failed: \(error.localizedDescription, privacy: .public)")
            return bundled
        }
    }

    /// Подменяет TileJSON-адрес векторного источника `openmaptiles`.
    static func patch(styleData: Data, tilesURL: URL) throws -> Data {
        guard var style = try JSONSerialization.jsonObject(with: styleData) as? [String: Any],
              var sources = style["sources"] as? [String: Any],
              var omt = sources["openmaptiles"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        omt["url"] = tilesURL.absoluteString
        sources["openmaptiles"] = omt
        style["sources"] = sources
        return try JSONSerialization.data(withJSONObject: style)
    }
}

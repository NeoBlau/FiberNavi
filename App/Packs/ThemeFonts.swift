import SwiftUI
import CoreText
import os

/// Регистрирует шрифты из пака и отдаёт Font по роли с системной заменой.
final class ThemeFonts {
    enum Role { case title, digits, body }

    private var names: [Role: String] = [:]
    private let fallbackDesign: Font.Design
    private let fallbackWeight: Font.Weight
    private static var registered: [URL: String] = [:]
    private static let log = Logger(subsystem: "local.fibernavi", category: "fonts")

    init(pack: UserPack, tokens: ThemeTokens.Fonts) {
        fallbackDesign = tokens.fallbackDesign
        fallbackWeight = tokens.fallbackWeight
        let keys: [(Role, String)] = [(.title, tokens.titleKey), (.digits, tokens.digitsKey), (.body, tokens.bodyKey)]
        for (role, key) in keys {
            if let url = pack.url(for: key), let name = Self.register(url) {
                names[role] = name
            }
        }
    }

    func font(_ role: Role, size: CGFloat) -> Font {
        if let name = names[role] {
            return .custom(name, size: size)
        }
        let weight: Font.Weight = role == .body ? .regular : fallbackWeight
        let design: Font.Design = role == .digits && fallbackDesign == .default ? .rounded : fallbackDesign
        return .system(size: size, weight: weight, design: design)
    }

    /// Возвращает PostScript-имя зарегистрированного шрифта.
    private static func register(_ url: URL) -> String? {
        if let name = registered[url] { return name }
        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let name = cgFont.postScriptName as String? else {
            log.warning("Unreadable font \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Уже зарегистрирован — не ошибка.
            log.debug("Font register: \(error?.takeRetainedValue().localizedDescription ?? "?", privacy: .public)")
        }
        registered[url] = name
        return name
    }
}

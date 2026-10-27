import SwiftUI
import CoreLocation
import Observation

/// Переключает тему целиком: стиль карты, HUD-токены, метки, шрифты, звуки, голос.
@Observable
final class ThemeManager {
    enum DaylightMode: String, CaseIterable, Identifiable {
        case auto, day, night
        var id: String { rawValue }
    }

    private(set) var theme: ThemeID
    private(set) var tokens: ThemeTokens
    private(set) var pack: UserPack
    private(set) var fonts: ThemeFonts
    private(set) var variant: StyleVariant = .day
    private(set) var styleURL: URL
    /// Картинки для стиля: метки `blip.*` и паттерны `pattern.*`.
    private(set) var mapImages: [String: UIImage] = [:]

    var daylightMode: DaylightMode {
        didSet {
            defaults.set(daylightMode.rawValue, forKey: Self.daylightKey)
            refreshVariant()
        }
    }

    let sounds = UISoundPlayer()
    private let defaults: UserDefaults
    private var lastCoordinate = AppConfig.defaultCenter
    private static let themeKey = "fn.theme"
    private static let daylightKey = "fn.daylight"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.themeKey).flatMap(ThemeID.init(rawValue:)) ?? ThemeRegistry.defaultTheme
        let tokens = ThemeRegistry.tokens(for: saved)
        let pack = UserPack.load(saved)
        theme = saved
        self.tokens = tokens
        self.pack = pack
        fonts = ThemeFonts(pack: pack, tokens: tokens.fonts)
        daylightMode = defaults.string(forKey: Self.daylightKey).flatMap(DaylightMode.init(rawValue:)) ?? .auto
        styleURL = StyleCompiler.styleURL(theme: saved, variant: .day, tilesURL: AppConfig.current.tilesURL)
        mapImages = Self.buildImages(pack: pack, tokens: tokens)
        refreshVariant()
    }

    func select(_ id: ThemeID) {
        guard id != theme else { return }
        theme = id
        tokens = ThemeRegistry.tokens(for: id)
        pack = UserPack.load(id)
        fonts = ThemeFonts(pack: pack, tokens: tokens.fonts)
        mapImages = Self.buildImages(pack: pack, tokens: tokens)
        defaults.set(id.rawValue, forKey: Self.themeKey)
        reloadStyle()
        sounds.play("ui.mission_start", from: pack)
    }

    /// Перечитать пак (после импорта файлов) и настройки сервера.
    func reload() {
        pack = UserPack.load(theme)
        fonts = ThemeFonts(pack: pack, tokens: tokens.fonts)
        mapImages = Self.buildImages(pack: pack, tokens: tokens)
        reloadStyle()
    }

    func updateDaylight(at coordinate: CLLocationCoordinate2D, date: Date = Date()) {
        lastCoordinate = coordinate
        refreshVariant(date: date)
    }

    func playUISound(_ key: String) {
        sounds.play(key, from: pack)
    }

    private func refreshVariant(date: Date = Date()) {
        let next: StyleVariant = switch daylightMode {
        case .day: .day
        case .night: .night
        case .auto: SolarCalculator.isNight(at: lastCoordinate, date: date) ? .night : .day
        }
        if next != variant {
            variant = next
            reloadStyle()
        }
    }

    private func reloadStyle() {
        styleURL = StyleCompiler.styleURL(theme: theme, variant: variant, tilesURL: AppConfig.current.tilesURL)
    }

    private static func buildImages(pack: UserPack, tokens: ThemeTokens) -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        for entry in BlipCatalog.entries {
            images[entry.key] = pack.image(entry.key)
                ?? StubArt.blip(entry, tint: tokens.blipTint, background: tokens.blipBackground)
        }
        images["pattern.paper"] = pack.image("map.tex.paper") ?? StubArt.paper()
        images["pattern.hatch"] = pack.image("map.tex.hatch") ?? StubArt.hatch()
        images["pattern.water"] = pack.image("map.tex.water") ?? StubArt.hatch(color: UIColor(white: 1, alpha: 0.25))
        images["pattern.grass"] = pack.image("map.tex.grass") ?? StubArt.hatch(color: UIColor(white: 0, alpha: 0.15), spacing: 4)
        return images
    }
}

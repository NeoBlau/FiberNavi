import SwiftUI
import UIKit

enum ThemeID: String, CaseIterable, Codable, Identifiable {
    case sanAndreas, gta5, rdr2, gta6concept
    var id: String { rawValue }
}

/// Все визуальные параметры темы. Вьюхи берут цвета, размеры и шрифты только отсюда.
struct ThemeTokens {
    struct Palette {
        var panel: Color
        var panelText: Color
        var secondaryText: Color
        var accent: Color
        var warning: Color
        var minimapRim: Color
        var route: UIColor
        var routeCasing: UIColor
        var routeGlow: UIColor?
    }

    enum MinimapShape: Equatable {
        case circle
        case roundedRect(cornerRadius: CGFloat)
    }

    enum Overlay: Equatable {
        case none
        /// Зерно и лёгкая пикселизация (SA).
        case grain(opacity: Double)
        /// Сепия и виньетка (RDR2).
        case vignette(color: Color, intensity: Double)
    }

    enum BannerStyle: Equatable {
        /// Тёмная плашка-подсказка в левом верхнем углу.
        case hint
        /// Карточка-сообщение в телефоне персонажа.
        case phoneMessage
        /// Строгая панель сверху.
        case panel
    }

    struct Fonts {
        /// Ключи шрифтов в паке и системные замены.
        var titleKey = "font.title"
        var digitsKey = "font.digits"
        var bodyKey = "font.body"
        var fallbackDesign: Font.Design = .default
        var fallbackWeight: Font.Weight = .semibold
    }

    var displayName: String
    var subtitle: String
    var palette: Palette
    var fonts: Fonts
    var minimapShape: MinimapShape
    var minimapAlignment: Alignment
    var minimapShowsNorth: Bool
    var minimapRimWidth: CGFloat
    var routeWidth: CGFloat
    var routeDash: [Double]?
    var cameraPitch: Double
    var overlay: Overlay
    var banner: BannerStyle
    var cornerRadius: CGFloat
    var spacing: CGFloat = 12
    /// Цвет заглушек меток по категориям, если в паке нет PNG.
    var blipTint: UIColor
    var blipBackground: UIColor
    /// Персонажи темы: id папки в `voice/` и подпись.
    var characters: [(id: String, name: String)]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

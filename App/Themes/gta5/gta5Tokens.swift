import SwiftUI

extension ThemeTokens {
    static let gta5 = ThemeTokens(
        displayName: "Лос-Сантос",
        subtitle: "В духе GTA V",
        palette: Palette(
            panel: Color(hex: 0x111315, alpha: 0.82),
            panelText: Color(hex: 0xFFFFFF),
            secondaryText: Color(hex: 0xB9BEC4),
            accent: Color(hex: 0xA65BD9),
            warning: Color(hex: 0xE04848),
            minimapRim: Color(hex: 0x000000, alpha: 0.85),
            route: UIColor(hex: 0xB45FE6),
            routeCasing: UIColor(hex: 0x3B1950),
            routeGlow: UIColor(hex: 0xC77DFF, alpha: 0.55)
        ),
        fonts: Fonts(fallbackDesign: .default, fallbackWeight: .bold),
        minimapShape: .roundedRect(cornerRadius: 10),
        minimapAlignment: .bottomLeading,
        minimapShowsNorth: false,
        minimapRimWidth: 4,
        routeWidth: 7,
        routeDash: nil,
        cameraPitch: 30,
        overlay: .none,
        banner: .panel,
        cornerRadius: 6,
        blipTint: UIColor(hex: 0xFFFFFF),
        blipBackground: UIColor(hex: 0x1B1D20),
        characters: [VoiceCharacter(id: "franklin", name: "Франклин"), VoiceCharacter(id: "michael", name: "Майкл"), VoiceCharacter(id: "trevor", name: "Тревор")]
    )
}

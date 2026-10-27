import SwiftUI

extension ThemeTokens {
    static let gta6concept = ThemeTokens(
        displayName: "Леонида",
        subtitle: "Концепт по мотивам трейлеров GTA VI",
        palette: Palette(
            panel: Color(hex: 0x1A1430, alpha: 0.55),
            panelText: Color(hex: 0xFFFFFF),
            secondaryText: Color(hex: 0xD6CCF5),
            accent: Color(hex: 0xFF5FA8),
            warning: Color(hex: 0xFF4D6D),
            minimapRim: Color(hex: 0xFFFFFF, alpha: 0.35),
            route: UIColor(hex: 0x4FE3FF),
            routeCasing: UIColor(hex: 0x0B2A44),
            routeGlow: UIColor(hex: 0x4FE3FF, alpha: 0.6)
        ),
        fonts: Fonts(fallbackDesign: .rounded, fallbackWeight: .semibold),
        minimapShape: .roundedRect(cornerRadius: 22),
        minimapAlignment: .bottomLeading,
        minimapShowsNorth: false,
        minimapRimWidth: 1,
        routeWidth: 6,
        routeDash: nil,
        cameraPitch: 55,
        overlay: .none,
        banner: .phoneMessage,
        cornerRadius: 18,
        blipTint: UIColor(hex: 0xFFFFFF),
        blipBackground: UIColor(hex: 0xFF5FA8),
        characters: [(id: "lucia", name: "Лусия"), (id: "jason", name: "Джейсон")]
    )
}

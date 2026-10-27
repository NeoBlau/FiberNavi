import SwiftUI

extension ThemeTokens {
    static let sanAndreas = ThemeTokens(
        displayName: "Сан-Андреас",
        subtitle: "В духе GTA San Andreas",
        palette: Palette(
            panel: Color(hex: 0x000000, alpha: 0.7),
            panelText: Color(hex: 0xFFFFFF),
            secondaryText: Color(hex: 0xD8D8C8),
            accent: Color(hex: 0xE4C34A),
            warning: Color(hex: 0xC8302C),
            minimapRim: Color(hex: 0x000000),
            route: UIColor(hex: 0xD24AD2),
            routeCasing: UIColor(hex: 0x2A0A2A),
            routeGlow: nil
        ),
        fonts: Fonts(fallbackDesign: .default, fallbackWeight: .heavy),
        minimapShape: .circle,
        minimapAlignment: .bottomLeading,
        minimapShowsNorth: true,
        minimapRimWidth: 5,
        routeWidth: 9,
        routeDash: nil,
        cameraPitch: 0,
        overlay: .grain(opacity: 0.12),
        banner: .hint,
        cornerRadius: 2,
        blipTint: UIColor(hex: 0xFFFFFF),
        blipBackground: UIColor(hex: 0x202020),
        characters: [VoiceCharacter(id: "cj", name: "Си-Джей")]
    )
}

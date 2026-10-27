import SwiftUI

extension ThemeTokens {
    static let rdr2 = ThemeTokens(
        displayName: "Фронтир",
        subtitle: "В духе Red Dead Redemption 2",
        palette: Palette(
            panel: Color(hex: 0x1E160E, alpha: 0.85),
            panelText: Color(hex: 0xF2E4C4),
            secondaryText: Color(hex: 0xC9B48C),
            accent: Color(hex: 0x9E1B1B),
            warning: Color(hex: 0xC2341F),
            minimapRim: Color(hex: 0x2B2015),
            route: UIColor(hex: 0x9E1B1B),
            routeCasing: UIColor(hex: 0xE2D1A8, alpha: 0.6),
            routeGlow: nil
        ),
        fonts: Fonts(fallbackDesign: .serif, fallbackWeight: .bold),
        minimapShape: .circle,
        minimapAlignment: .bottomLeading,
        minimapShowsNorth: true,
        minimapRimWidth: 7,
        routeWidth: 5,
        routeDash: [2, 1.5],
        cameraPitch: 0,
        overlay: .vignette(color: Color(hex: 0x3A2610), intensity: 0.55),
        banner: .hint,
        cornerRadius: 3,
        blipTint: UIColor(hex: 0x2B2015),
        blipBackground: UIColor(hex: 0xE2D1A8),
        characters: [(id: "arthur", name: "Артур Морган")]
    )
}

import SwiftUI

/// Постобработка поверх карты: зерно SA, виньетка и сепия RDR2. Не перехватывает касания.
struct ThemeOverlay: View {
    let overlay: ThemeTokens.Overlay
    private static let grainTile = StubArt.grain()

    var body: some View {
        Group {
            switch overlay {
            case .none:
                EmptyView()
            case .grain(let opacity):
                Image(uiImage: Self.grainTile)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
                    .blendMode(.overlay)
                    .opacity(opacity)
            case .vignette(let color, let intensity):
                RadialGradient(colors: [.clear, color.opacity(intensity)],
                               center: .center, startRadius: 120, endRadius: 520)
                    .blendMode(.multiply)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

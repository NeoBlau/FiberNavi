import SwiftUI

/// Форма мини-карты темы.
struct MinimapShape: Shape {
    let kind: ThemeTokens.MinimapShape

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            Path(ellipseIn: rect)
        case .roundedRect(let radius):
            Path(roundedRect: rect, cornerRadius: radius)
        }
    }
}

/// Обод мини-карты: рамка из пака (`hud.minimap_frame`) или нарисованный обод, буква N.
struct RadarFrame: View {
    let tokens: ThemeTokens
    let frameImage: UIImage?
    let fonts: ThemeFonts
    /// Поворот карты в градусах (для буквы N при автоповороте).
    var mapHeading: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let frameImage {
                    Image(uiImage: frameImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    MinimapShape(kind: tokens.minimapShape)
                        .stroke(tokens.palette.minimapRim, lineWidth: tokens.minimapRimWidth)
                }
                if tokens.minimapShowsNorth {
                    let r = min(geo.size.width, geo.size.height) / 2
                    let angle = Angle.degrees(-mapHeading - 90).radians
                    Text("N")
                        .font(fonts.font(.title, size: 15))
                        .foregroundStyle(tokens.palette.panelText)
                        .padding(4)
                        .background(Circle().fill(tokens.palette.minimapRim))
                        .position(x: geo.size.width / 2 + cos(angle) * r,
                                  y: geo.size.height / 2 + sin(angle) * r)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

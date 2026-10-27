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
                    northLabel
                        .position(northPosition(in: geo.size))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var northLabel: some View {
        Text("N")
            .font(fonts.font(.title, size: 15))
            .foregroundStyle(tokens.palette.panelText)
            .padding(4)
            .background(Circle().fill(tokens.palette.minimapRim))
    }

    /// Точка на ободе, куда указывает север при текущем повороте карты.
    private func northPosition(in size: CGSize) -> CGPoint {
        let radius = Double(min(size.width, size.height)) / 2
        let angle = (-mapHeading - 90) * Double.pi / 180
        let x = Double(size.width) / 2 + cos(angle) * radius
        let y = Double(size.height) / 2 + sin(angle) * radius
        return CGPoint(x: x, y: y)
    }
}

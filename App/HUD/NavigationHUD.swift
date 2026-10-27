import SwiftUI

/// Панель следующего манёвра. Внешний вид — по `tokens.banner`.
struct ManeuverBanner: View {
    let maneuver: Maneuver
    let distance: Double
    let next: Maneuver?
    let tokens: ThemeTokens
    let fonts: ThemeFonts
    /// Мигание стрелки при объявлении (фолбэк без слов — слой 3 озвучки).
    var flash = false

    var body: some View {
        switch tokens.banner {
        case .hint: hint
        case .panel: panel
        case .phoneMessage: phoneMessage
        }
    }

    private var street: String {
        maneuver.streetNames.first ?? maneuver.instruction
    }

    private var arrow: some View {
        Image(systemName: maneuver.kind.symbol)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(tokens.palette.panelText)
            .scaleEffect(flash ? 1.25 : 1)
            .opacity(flash ? 0.6 : 1)
            .animation(flash ? .easeInOut(duration: 0.25).repeatCount(4, autoreverses: true) : .default, value: flash)
            .frame(width: 48)
            .accessibilityHidden(true)
    }

    private var distanceText: some View {
        Text(Format.distance(distance))
            .font(fonts.font(.digits, size: 30))
            .foregroundStyle(tokens.palette.panelText)
            .monospacedDigit()
    }

    /// SA / RDR2: тёмная полупрозрачная подсказка в левом верхнем углу.
    private var hint: some View {
        HStack(alignment: .center, spacing: tokens.spacing) {
            arrow
            VStack(alignment: .leading, spacing: 2) {
                distanceText
                Text(street)
                    .font(fonts.font(.body, size: 16))
                    .foregroundStyle(tokens.palette.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(tokens.spacing)
        .frame(maxWidth: 320, alignment: .leading)
        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// GTA V: строгая панель во всю ширину, следующий манёвр мелко.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: tokens.spacing) {
                arrow
                distanceText
                Spacer(minLength: 0)
            }
            Text(street)
                .font(fonts.font(.title, size: 18))
                .foregroundStyle(tokens.palette.panelText)
                .lineLimit(2)
            if let next, next.kind != .arrive {
                Label("Затем", systemImage: next.kind.symbol)
                    .font(fonts.font(.body, size: 13))
                    .foregroundStyle(tokens.palette.secondaryText)
            }
        }
        .padding(tokens.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .overlay(alignment: .leading) {
            Rectangle().fill(tokens.palette.accent).frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius))
        }
        .accessibilityElement(children: .combine)
    }

    /// GTA VI концепт: карточка-сообщение в телефоне персонажа.
    private var phoneMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [tokens.palette.accent, Color(uiColor: tokens.palette.route)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: maneuver.kind.symbol).foregroundStyle(.white).font(.headline))
            VStack(alignment: .leading, spacing: 4) {
                Text("через \(Format.distance(distance))")
                    .font(fonts.font(.digits, size: 22))
                    .foregroundStyle(tokens.palette.panelText)
                Text(street)
                    .font(fonts.font(.body, size: 15))
                    .foregroundStyle(tokens.palette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: tokens.cornerRadius).stroke(.white.opacity(0.25), lineWidth: 1))
        .scaleEffect(flash ? 1.03 : 1)
        .animation(.spring(duration: 0.3), value: flash)
        .accessibilityElement(children: .combine)
    }
}

/// Низ экрана: прибытие, остаток, скорость и лимит, кнопка «стоп».
struct TripBar: View {
    let progress: NavigationProgress
    let speed: Double
    let speedLimit: Double?
    let tokens: ThemeTokens
    let fonts: ThemeFonts
    let isOffRoute: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: tokens.spacing) {
            SpeedIndicator(speed: speed, limit: speedLimit, tokens: tokens, fonts: fonts)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.eta(after: progress.remainingTime))
                    .font(fonts.font(.digits, size: 24))
                    .foregroundStyle(tokens.palette.panelText)
                Text("\(Format.duration(progress.remainingTime)) · \(Format.distance(progress.remainingDistance))")
                    .font(fonts.font(.body, size: 14))
                    .foregroundStyle(tokens.palette.secondaryText)
                if isOffRoute {
                    Text("Вне маршрута")
                        .font(fonts.font(.body, size: 13))
                        .foregroundStyle(tokens.palette.warning)
                }
            }
            Spacer(minLength: 0)
            Button(action: onStop) {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tokens.palette.warning, in: Circle())
            }
            .accessibilityLabel("Завершить маршрут")
        }
        .padding(tokens.spacing)
        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
    }
}

/// Текущая скорость с лимитом. Для GTA V под ней полоска «скорость относительно лимита».
struct SpeedIndicator: View {
    let speed: Double
    let limit: Double?
    let tokens: ThemeTokens
    let fonts: ThemeFonts

    private var kmh: Int { Int((speed * 3.6).rounded()) }
    private var isSpeeding: Bool { limit.map { Double(kmh) > $0 + 5 } ?? false }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Text("\(kmh)")
                    .font(fonts.font(.digits, size: 28))
                    .monospacedDigit()
                    .foregroundStyle(isSpeeding ? tokens.palette.warning : tokens.palette.panelText)
                    .frame(width: 64, height: 52)
                if let limit {
                    Text("\(Int(limit))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white))
                        .overlay(Circle().stroke(.red, lineWidth: 3))
                        .offset(x: 10, y: -10)
                        .accessibilityLabel("Ограничение \(Int(limit))")
                }
            }
            if tokens.banner == .panel {
                GeometryReader { geo in
                    let ratio = min(1, Double(kmh) / max(1, (limit ?? 90) * 1.2))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.2))
                        Rectangle().fill(isSpeeding ? tokens.palette.warning : Color(hex: 0x4FB35A))
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(width: 64, height: 4)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Скорость \(kmh) километров в час")
    }
}

import UIKit

/// Метки POI, на которые ссылаются стили (`icon-image`). Должен совпадать с
/// BLIP_CLASSES в tools/style_builder/build_styles.py — это проверяет тест.
enum BlipCatalog {
    struct Entry {
        let key: String
        let symbol: String
        /// Буква вместо символа (метро).
        let letter: String?
        let color: UIColor
    }

    static let entries: [Entry] = [
        Entry(key: "blip.gas_station", symbol: "fuelpump.fill", letter: nil, color: UIColor(hex: 0xE8A33A)),
        Entry(key: "blip.food", symbol: "fork.knife", letter: nil, color: UIColor(hex: 0xE0623A)),
        Entry(key: "blip.atm", symbol: "banknote.fill", letter: nil, color: UIColor(hex: 0x4FB35A)),
        Entry(key: "blip.parking", symbol: "parkingsign", letter: nil, color: UIColor(hex: 0x3A7BE0)),
        Entry(key: "blip.hospital", symbol: "cross.fill", letter: nil, color: UIColor(hex: 0xE04848)),
        Entry(key: "blip.pharmacy", symbol: "pills.fill", letter: nil, color: UIColor(hex: 0x3AC27A)),
        Entry(key: "blip.shop", symbol: "bag.fill", letter: nil, color: UIColor(hex: 0x8E6AD8)),
        Entry(key: "blip.police", symbol: "shield.fill", letter: nil, color: UIColor(hex: 0x2F5BD0)),
        Entry(key: "blip.car_service", symbol: "wrench.and.screwdriver.fill", letter: nil, color: UIColor(hex: 0x9AA0A6)),
        Entry(key: "blip.metro", symbol: "", letter: "M", color: UIColor(hex: 0xD52B1E)),
        Entry(key: "blip.rail", symbol: "tram.fill", letter: nil, color: UIColor(hex: 0x6B7280)),
        Entry(key: "blip.waypoint", symbol: "mappin", letter: nil, color: UIColor(hex: 0xF2C230)),
        Entry(key: "blip.generic", symbol: "circle.fill", letter: nil, color: UIColor(hex: 0x9AA0A6)),
    ]

    static var keys: [String] { entries.map(\.key) }
}

/// Нейтральные заглушки, когда в паке нет файла. Всё рисуется кодом, ничего из игр.
enum StubArt {
    /// Круглая метка 48×48 pt: фон темы, цветной обод, белый символ.
    static func blip(_ entry: BlipCatalog.Entry, tint: UIColor, background: UIColor) -> UIImage {
        let size = CGSize(width: 48, height: 48)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            background.setFill()
            UIBezierPath(ovalIn: rect).fill()
            entry.color.setStroke()
            let rim = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            rim.lineWidth = 4
            rim.stroke()

            if let letter = entry.letter {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .black),
                    .foregroundColor: entry.color,
                ]
                let text = NSAttributedString(string: letter, attributes: attrs)
                let b = text.size()
                text.draw(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
            } else if let symbol = UIImage(systemName: entry.symbol,
                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)) {
                let glyph = symbol.withTintColor(tint, renderingMode: .alwaysOriginal)
                let g = glyph.size
                glyph.draw(in: CGRect(x: (size.width - g.width) / 2, y: (size.height - g.height) / 2,
                                      width: g.width, height: g.height))
            }
            _ = ctx
        }
    }

    /// Бумажная фактура: светлый шум. Используется как `pattern.paper`.
    static func paper(seed: UInt64 = 7) -> UIImage {
        noise(size: 128, seed: seed) { v in UIColor(white: 0.5 + v * 0.5, alpha: 0.35 * v) }
    }

    /// Диагональная штриховка: `pattern.hatch`.
    static func hatch(color: UIColor = UIColor(white: 0.2, alpha: 0.5), spacing: CGFloat = 6) -> UIImage {
        let side: CGFloat = spacing * 4
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(1)
            var x: CGFloat = -side
            while x < side * 2 {
                cg.move(to: CGPoint(x: x, y: side))
                cg.addLine(to: CGPoint(x: x + side, y: 0))
                x += spacing
            }
            cg.strokePath()
        }
    }

    /// Плитка зерна для оверлея SA.
    static func grain(seed: UInt64 = 42) -> UIImage {
        noise(size: 96, seed: seed) { v in UIColor(white: v, alpha: 1) }
    }

    private static func noise(size: Int, seed: UInt64, color: (CGFloat) -> UIColor) -> UIImage {
        var rng = SplitMix64(seed: seed)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            for y in 0..<size {
                for x in 0..<size {
                    color(CGFloat(rng.nextUnit())).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}

/// Детерминированный генератор, чтобы заглушки не менялись между запусками.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

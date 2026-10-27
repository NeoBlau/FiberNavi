import Foundation

/// Единственное место регистрации тем. Новая тема = папка в App/Themes + строка здесь
/// + палитра в tools/style_builder/palettes.
enum ThemeRegistry {
    static func tokens(for id: ThemeID) -> ThemeTokens {
        switch id {
        case .sanAndreas: .sanAndreas
        case .gta5: .gta5
        case .rdr2: .rdr2
        case .gta6concept: .gta6concept
        }
    }

    static let defaultTheme: ThemeID = .gta5
}

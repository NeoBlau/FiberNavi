import SwiftUI

/// Выбор темы. Шит на половину экрана: карта за ним перекрашивается сразу — это и есть живое превью.
struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var themes = themes
        NavigationStack {
            List {
                Section {
                    ForEach(ThemeID.allCases) { id in
                        row(id)
                    }
                }
                Section("Время суток") {
                    Picker("Режим", selection: $themes.daylightMode) {
                        Text("Авто").tag(ThemeManager.DaylightMode.auto)
                        Text("День").tag(ThemeManager.DaylightMode.day)
                        Text("Ночь").tag(ThemeManager.DaylightMode.night)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Проверить звук темы") { themes.playUISound("ui.waypoint") }
                } footer: {
                    Text(packStatus)
                }
            }
            .navigationTitle("Тема")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func row(_ id: ThemeID) -> some View {
        let tokens = ThemeRegistry.tokens(for: id)
        return Button {
            themes.select(id)
        } label: {
            HStack(spacing: 14) {
                MinimapShape(kind: tokens.minimapShape)
                    .fill(Color(uiColor: tokens.palette.route))
                    .overlay(MinimapShape(kind: tokens.minimapShape).stroke(tokens.palette.minimapRim, lineWidth: 3))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tokens.displayName).font(.headline)
                    Text(tokens.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if themes.theme == id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tokens.palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(themes.theme == id ? .isSelected : [])
    }

    private var packStatus: String {
        let pack = themes.pack
        guard pack.isInstalled else {
            return "Пак ассетов не найден: работают заглушки. Положи файлы в Assets/UserPacks/\(themes.theme.rawValue)/ или в «Файлы» → FiberNavi → UserPacks."
        }
        let missing = pack.missingKeys
        return missing.isEmpty ? "Пак установлен полностью." : "Пак установлен, не хватает: \(missing.joined(separator: ", "))."
    }
}

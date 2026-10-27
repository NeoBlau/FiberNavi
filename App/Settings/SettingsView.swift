import SwiftUI
import UniformTypeIdentifiers

/// Настройки: сервер, перестроение, камера, голос, отладка.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themes
    @Environment(VoiceSettings.self) private var voice
    @Bindable var session: NavigationSession
    @Bindable var camera: CameraController

    @AppStorage(AppConfig.Key.routing) private var routingURL = ""
    @AppStorage(AppConfig.Key.search) private var searchURL = ""
    @AppStorage(AppConfig.Key.tiles) private var tilesURL = ""
    @State private var importingGPX = false

    var body: some View {
        @Bindable var voice = voice
        NavigationStack {
            Form {
                Section {
                    TextField("Valhalla, напр. http://192.168.1.10:8002", text: $routingURL)
                    TextField("Photon, напр. http://192.168.1.10:2322", text: $searchURL)
                    TextField("Тайлы (TileJSON), пусто — OpenFreeMap", text: $tilesURL)
                } header: {
                    Text("Сервер")
                } footer: {
                    Text("Бэкенд из папки Backend/. Адреса тайлов применяются после смены темы или перезапуска.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                Section("Перестроение маршрута") {
                    Stepper("Порог: \(Int(session.rerouteSettings.offRouteDistance)) м",
                            value: $session.rerouteSettings.offRouteDistance, in: 20...150, step: 10)
                    Stepper("Задержка: \(Int(session.rerouteSettings.delay)) с",
                            value: $session.rerouteSettings.delay, in: 1...15, step: 1)
                }

                Section("Карта") {
                    Toggle("Север всегда сверху", isOn: $camera.northUpPreferred)
                }

                Section("Голос") {
                    Picker("Персонаж", selection: $voice.characterID) {
                        ForEach(themes.tokens.characters) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Только инструкции", isOn: $voice.instructionsOnly)
                    if !voice.instructionsOnly {
                        Picker("Болтовня", selection: $voice.chatter) {
                            ForEach(VoiceSettings.Chatter.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Фильтр мата", selection: $voice.profanity) {
                        ForEach(VoiceSettings.Profanity.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ForEach([40.0, 60.0, 90.0], id: \.self) { kmh in
                        Button("Проехать маршрут на \(Int(kmh)) км/ч") {
                            session.simulateRoute(speedKmh: kmh)
                            dismiss()
                        }
                        .disabled(session.selectedRoute == nil)
                    }
                    Button("Загрузить GPX-трек…") { importingGPX = true }
                    if session.isSimulating {
                        Button("Остановить симуляцию", role: .destructive) { session.stop() }
                    }
                } header: {
                    Text("Отладка")
                } footer: {
                    Text("Симуляция подаёт навигации точки GPS вдоль маршрута — проверка манёвров и голоса без поездки.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .fileImporter(isPresented: $importingGPX, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    session.simulateGPX(data)
                    dismiss()
                }
            }
        }
    }
}

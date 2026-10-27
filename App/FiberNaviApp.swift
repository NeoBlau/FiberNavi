import SwiftUI

@main
struct FiberNaviApp: App {
    @State private var location = LocationService()
    @State private var themes = ThemeManager()
    @State private var session = NavigationSession()
    @State private var places = PlacesStore()
    @State private var voiceSettings: VoiceSettings
    @State private var voice: VoiceDirector

    init() {
        let settings = VoiceSettings()
        _voiceSettings = State(initialValue: settings)
        _voice = State(initialValue: VoiceDirector(player: EngineVoicePlayer(), settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, voice: voice)
                .environment(location)
                .environment(themes)
                .environment(places)
                .environment(voiceSettings)
        }
    }
}

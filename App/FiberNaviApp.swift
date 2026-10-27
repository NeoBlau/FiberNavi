import SwiftUI

@main
struct FiberNaviApp: App {
    @State private var location = LocationService()
    @State private var themes = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(themes)
        }
    }
}

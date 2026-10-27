import SwiftUI

@main
struct FiberNaviApp: App {
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
        }
    }
}

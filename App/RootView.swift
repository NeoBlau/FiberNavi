import SwiftUI

struct RootView: View {
    @Environment(LocationService.self) private var location
    @State private var camera = CameraController()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapView(styleURL: AppConfig.current.mapStyleURL, camera: camera, mode: camera.mode)
                .ignoresSafeArea()

            Button {
                camera.followUser()
            } label: {
                Image(systemName: camera.isFollowing ? "location.fill" : "location")
                    .font(.title2)
                    .padding(14)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Показать моё местоположение")
            .padding(20)
        }
        .onAppear { location.requestAuthorization() }
    }
}

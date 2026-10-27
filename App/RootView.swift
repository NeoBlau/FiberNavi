import SwiftUI

struct RootView: View {
    enum MapMode { case full, radar }

    @Environment(LocationService.self) private var location
    @Environment(ThemeManager.self) private var themes
    @State private var camera = CameraController()
    @State private var mapMode: MapMode = .full
    @State private var showThemePicker = false
    @State private var transitionDim = 0.0

    var body: some View {
        let tokens = themes.tokens
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let radar = mapMode == .radar
                let side = min(geo.size.width, geo.size.height) * 0.62
                map
                    .frame(width: radar ? side : geo.size.width, height: radar ? side : geo.size.height)
                    .clipShape(radar ? AnyShape(MinimapShape(kind: tokens.minimapShape)) : AnyShape(Rectangle()))
                    .overlay {
                        if radar {
                            RadarFrame(tokens: tokens, frameImage: themes.pack.image("hud.minimap_frame"), fonts: themes.fonts)
                        }
                    }
                    .padding(radar ? 20 : 0)
                    .frame(width: geo.size.width, height: geo.size.height,
                           alignment: radar ? tokens.minimapAlignment : .center)
            }
            .ignoresSafeArea(edges: mapMode == .full ? .all : [])

            ThemeOverlay(overlay: tokens.overlay)

            Color.black.opacity(transitionDim).ignoresSafeArea().allowsHitTesting(false)

            controls(tokens)
        }
        .onAppear { location.requestAuthorization() }
        .task(id: themes.theme) {
            while !Task.isCancelled {
                themes.updateDaylight(at: location.lastLocation?.coordinate ?? AppConfig.defaultCenter)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerView()
        }
    }

    private var map: some View {
        MapView(styleURL: themes.styleURL,
                images: themes.mapImages,
                pitch: themes.tokens.cameraPitch,
                camera: camera,
                mode: camera.mode)
    }

    private func controls(_ tokens: ThemeTokens) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: tokens.spacing) {
                    roundButton("paintpalette.fill", label: "Тема", tokens: tokens) { showThemePicker = true }
                    roundButton(mapMode == .full ? "circle.circle" : "map.fill",
                                label: mapMode == .full ? "Радар" : "Полная карта",
                                tokens: tokens) { toggleMapMode() }
                }
            }
            Spacer()
            HStack {
                Spacer()
                roundButton(camera.isFollowing ? "location.fill" : "location",
                            label: "Показать моё местоположение", tokens: tokens) {
                    camera.followUser()
                }
            }
        }
        .padding(20)
    }

    private func roundButton(_ symbol: String, label: String, tokens: ThemeTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tokens.palette.panelText)
                .frame(width: 52, height: 52)
                .background(tokens.palette.panel, in: Circle())
        }
        .accessibilityLabel(label)
    }

    /// Переход как открытие большой карты в игре: быстрое затемнение и смена масштаба.
    private func toggleMapMode() {
        withAnimation(.easeIn(duration: 0.12)) { transitionDim = 0.6 }
        withAnimation(.spring(duration: 0.35).delay(0.08)) {
            mapMode = mapMode == .full ? .radar : .full
        }
        withAnimation(.easeOut(duration: 0.25).delay(0.2)) { transitionDim = 0 }
        themes.playUISound(mapMode == .full ? "ui.map_close" : "ui.map_open")
    }
}

import SwiftUI
import CoreLocation
import os

struct RootView: View {
    enum MapMode { case full, radar }

    @Environment(LocationService.self) private var location
    @Environment(ThemeManager.self) private var themes
    @Environment(VoiceSettings.self) private var voiceSettings
    @Bindable var session: NavigationSession
    let voice: VoiceDirector

    @State private var camera = CameraController()
    @State private var mapMode: MapMode = .full
    @State private var showThemePicker = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var transitionDim = 0.0
    @State private var flash = false

    private let log = Logger(subsystem: "local.fibernavi", category: "ui")

    var body: some View {
        let tokens = themes.tokens
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                mapContainer(size: geo.size, tokens: tokens)
            }
            .ignoresSafeArea(edges: mapMode == .full ? .all : [])

            ThemeOverlay(overlay: tokens.overlay)

            Color.black.opacity(transitionDim).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: tokens.spacing) {
                topArea(tokens)
                Spacer(minLength: 0)
                bottomArea(tokens)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear(perform: wire)
        .task(id: themes.theme) {
            while !Task.isCancelled {
                themes.updateDaylight(at: location.lastLocation?.coordinate ?? AppConfig.defaultCenter)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .task(id: "\(themes.theme.rawValue)/\(voiceSettings.characterID)") { loadVoice() }
        .onChange(of: session.state) { old, new in stateChanged(from: old, to: new) }
        .onChange(of: voice.lastFallbackAt) { pulse() }
        .onChange(of: session.lastAnnouncement) { pulse() }
        .sheet(isPresented: $showThemePicker) { ThemePickerView() }
        .sheet(isPresented: $showSearch) {
            SearchView(near: location.lastLocation?.coordinate) { place in
                Task { await session.plan(to: place, from: location.lastLocation) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(session: session, camera: camera) }
    }

    // MARK: Карта

    @ViewBuilder
    private func mapContainer(size: CGSize, tokens: ThemeTokens) -> some View {
        let radar = mapMode == .radar
        let side: CGFloat = min(size.width, size.height) * 0.62
        let shape: AnyShape = radar ? AnyShape(MinimapShape(kind: tokens.minimapShape)) : AnyShape(Rectangle())
        let alignment: Alignment = radar ? tokens.minimapAlignment : .center
        map
            .frame(width: radar ? side : size.width, height: radar ? side : size.height)
            .clipShape(shape)
            .overlay { radarRim(visible: radar, tokens: tokens) }
            .padding(radar ? 20 : 0)
            .frame(width: size.width, height: size.height, alignment: alignment)
    }

    @ViewBuilder
    private func radarRim(visible: Bool, tokens: ThemeTokens) -> some View {
        if visible {
            RadarFrame(tokens: tokens, frameImage: themes.pack.image("hud.minimap_frame"), fonts: themes.fonts,
                       mapHeading: camera.mode == .followCourse ? session.course : 0)
        }
    }

    private var map: some View {
        MapView(styleURL: themes.styleURL,
                images: themes.mapImages,
                pitch: themes.tokens.cameraPitch,
                routeStyle: RouteStyle(tokens: themes.tokens),
                overlay: overlayState,
                camera: camera,
                mode: camera.mode,
                onLongPress: { coordinate in Task { await planToPoint(coordinate) } })
    }

    private var overlayState: MapOverlayState {
        let route = session.selectedRoute
        let next = session.progress?.nextManeuver.flatMap { m in
            route.map { $0.coordinates[min(m.beginShapeIndex, $0.coordinates.count - 1)] }
        }
        let navigating = session.state == .navigating || session.state == .arrived
        return MapOverlayState(routes: session.routes, selectedIndex: session.selectedRouteIndex,
                               nextManeuver: navigating ? next : nil,
                               puck: navigating ? session.position : nil,
                               puckCourse: session.course,
                               followZoom: Self.followZoom(speed: session.speed))
    }

    /// Чем быстрее едем, тем дальше камера.
    static func followZoom(speed: Double) -> Double {
        let kmh = speed * 3.6
        switch kmh {
        case ..<25: return 17
        case ..<60: return 16.2
        case ..<90: return 15.4
        default: return 14.6
        }
    }

    // MARK: Верх и низ

    @ViewBuilder
    private func topArea(_ tokens: ThemeTokens) -> some View {
        if session.state == .navigating, let progress = session.progress, let maneuver = progress.nextManeuver {
            ManeuverBanner(maneuver: maneuver, distance: progress.distanceToManeuver, next: progress.maneuverAfter,
                           tokens: tokens, fonts: themes.fonts, flash: flash)
        } else if session.state != .navigating {
            HStack(alignment: .top, spacing: tokens.spacing) {
                Button { showSearch = true } label: {
                    Label("Куда едем?", systemImage: "magnifyingglass")
                        .font(themes.fonts.font(.body, size: 17))
                        .foregroundStyle(tokens.palette.panelText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
                }
                VStack(spacing: tokens.spacing) {
                    roundButton("paintpalette.fill", label: "Тема", tokens: tokens) { showThemePicker = true }
                    roundButton("gearshape.fill", label: "Настройки", tokens: tokens) { showSettings = true }
                }
            }
        }
        if let error = session.lastError {
            Text(error)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(10)
                .background(tokens.palette.warning.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .onTapGesture { Task { await clearErrorLater(0) } }
                .task { await clearErrorLater(6) }
        }
    }

    @ViewBuilder
    private func bottomArea(_ tokens: ThemeTokens) -> some View {
        HStack {
            Spacer()
            VStack(spacing: tokens.spacing) {
                roundButton(mapMode == .full ? "circle.circle" : "map.fill",
                            label: mapMode == .full ? "Радар" : "Полная карта", tokens: tokens) { toggleMapMode() }
                roundButton(camera.isFollowing ? "location.fill" : "location",
                            label: "Показать моё местоположение", tokens: tokens) { camera.followUser() }
            }
        }
        switch session.state {
        case .planning:
            ProgressView("Строю маршрут…")
                .tint(tokens.palette.panelText)
                .foregroundStyle(tokens.palette.panelText)
                .padding()
                .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        case .previewing:
            RoutePreviewPanel(session: session, tokens: tokens,
                              onStart: { session.start() },
                              onSimulate: { session.simulateRoute(speedKmh: 60) },
                              onReplan: replan)
        case .navigating:
            if let progress = session.progress {
                TripBar(progress: progress, speed: session.speed, speedLimit: session.speedLimit, tokens: tokens,
                        fonts: themes.fonts, isOffRoute: session.isOffRoute || session.isRerouting) {
                    session.stop()
                }
            }
        case .arrived:
            HStack {
                Label("Вы на месте", systemImage: "flag.checkered")
                    .font(themes.fonts.font(.title, size: 20))
                    .foregroundStyle(tokens.palette.panelText)
                Spacer()
                Button("Готово") { session.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(tokens.palette.accent)
            }
            .padding(tokens.spacing)
            .background(tokens.palette.panel, in: RoundedRectangle(cornerRadius: tokens.cornerRadius))
        case .idle:
            EmptyView()
        }
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

    // MARK: Логика

    private func wire() {
        location.requestAuthorization()
        location.onLocation = { [session] fix in
            if !session.isSimulating { session.ingest(fix) }
        }
        session.onEvent = { [voice] event in voice.handle(event) }
        session.isNight = { [themes] in themes.variant == .night }
        voice.isNight = { [themes] in themes.variant == .night }
        voice.currentSpeed = { [session] in session.speed }
        voice.playFallbackSound = { [themes] in themes.playUISound("ui.waypoint") }
    }

    private func loadVoice() {
        let characters = themes.tokens.characters
        if !characters.contains(where: { $0.id == voiceSettings.characterID }), let first = characters.first {
            voiceSettings.characterID = first.id
            return // task перезапустится с новым id
        }
        guard let url = themes.pack.voiceManifestURL(character: voiceSettings.characterID) else {
            voice.bank = nil
            return
        }
        do {
            voice.bank = try PhraseBank.load(from: url)
        } catch {
            voice.bank = nil
            log.warning("Voice manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stateChanged(from old: NavigationSession.State, to new: NavigationSession.State) {
        switch new {
        case .previewing:
            camera.userDidPan()
        case .navigating:
            location.beginNavigationSession()
            camera.followUser()
            if old != .navigating { themes.playUISound("ui.mission_start") }
        case .arrived:
            themes.playUISound("ui.arrived")
            location.endNavigationSession()
        case .idle:
            location.endNavigationSession()
            voice.stopAll()
        case .planning:
            break
        }
    }

    private func replan() {
        guard let destination = session.destination else { return }
        Task { await session.plan(to: destination, from: location.lastLocation) }
    }

    private func planToPoint(_ coordinate: CLLocationCoordinate2D) async {
        guard session.state == .idle || session.state == .previewing else { return }
        var place = Place(id: "pin:\(coordinate.latitude),\(coordinate.longitude)", name: "Точка на карте",
                          subtitle: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
                          latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let url = AppConfig.current.searchURL, let found = try? await PhotonClient(baseURL: url).reverse(coordinate) {
            place.name = found.name
            place.subtitle = found.subtitle
        }
        themes.playUISound("ui.waypoint")
        await session.plan(to: place, from: location.lastLocation)
    }

    private func pulse() {
        flash = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            flash = false
        }
    }

    private func clearErrorLater(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        session.clearError()
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

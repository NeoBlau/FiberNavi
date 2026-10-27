import Foundation
import CoreLocation
import Observation
import os

/// Связывает поиск маршрута, привязку к линии, манёвры, перестроение и события для голоса.
@Observable
final class NavigationSession {
    enum State: Equatable { case idle, planning, previewing, navigating, arrived }

    private(set) var state: State = .idle
    private(set) var routes: [Route] = []
    var selectedRouteIndex = 0
    private(set) var destination: Place?
    var mode: TravelMode = .auto

    private(set) var progress: NavigationProgress?
    /// Позиция, привязанная к маршруту (во время ведения) или сырая.
    private(set) var position: CLLocationCoordinate2D?
    private(set) var course: Double = 0
    /// м/с
    private(set) var speed: Double = 0
    /// км/ч
    private(set) var speedLimit: Double?
    private(set) var isOffRoute = false
    private(set) var isRerouting = false
    private(set) var isSimulating = false
    private(set) var lastError: String?
    /// Последнее объявление манёвра — HUD мигает стрелкой.
    private(set) var lastAnnouncement: ManeuverEngine.Announcement?

    var rerouteSettings = RerouteService.Settings() {
        didSet { reroute.settings = rerouteSettings }
    }

    /// Получатель событий (VoiceDirector).
    var onEvent: ((GuidanceEvent) -> Void)?
    /// Ночь ли сейчас — для реплики «ночная езда».
    var isNight: () -> Bool = { false }

    private let engineProvider: () -> RoutingEngine?
    private var matcher: MapMatcher?
    private var maneuvers: ManeuverEngine?
    private var reroute = RerouteService()
    private var monitor = DrivingMonitor()
    private var simulationTask: Task<Void, Never>?
    private var lastLocation: CLLocation?
    private var arrivalAnnounced = false
    private let log = Logger(subsystem: "local.fibernavi", category: "navigation")

    init(engineProvider: @escaping () -> RoutingEngine? = NavigationSession.defaultEngine) {
        self.engineProvider = engineProvider
    }

    static func defaultEngine() -> RoutingEngine? {
        AppConfig.current.routingURL.map { ValhallaClient(baseURL: $0) }
    }

    var selectedRoute: Route? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }

    // MARK: Планирование

    @MainActor
    func plan(to place: Place, from origin: CLLocation?) async {
        destination = place
        lastError = nil
        guard let engine = engineProvider() else {
            lastError = RoutingError.notConfigured.localizedDescription
            state = .idle
            return
        }
        let from = origin?.coordinate ?? AppConfig.defaultCenter
        state = .planning
        let started = Date()
        do {
            let heading = (origin?.course ?? -1) >= 0 ? origin?.course : nil
            routes = try await engine.routes(from: from, heading: heading, to: place.coordinate, mode: mode, alternatives: 2)
            selectedRouteIndex = 0
            state = .previewing
            log.info("Routes in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
        } catch {
            lastError = error.localizedDescription
            state = .idle
        }
    }

    func clearError() { lastError = nil }

    func cancelPreview() {
        stop()
        routes = []
        destination = nil
        state = .idle
    }

    // MARK: Ведение

    func start() {
        guard let route = selectedRoute else { return }
        install(route)
        routes = [route]
        selectedRouteIndex = 0
        arrivalAnnounced = false
        monitor = DrivingMonitor()
        reroute = RerouteService(settings: rerouteSettings)
        state = .navigating
        onEvent?(.routeStarted)
        if isNight() { onEvent?(.nightDriving) }
        if let lastLocation { ingest(lastLocation) }
    }

    func stop() {
        simulationTask?.cancel()
        simulationTask = nil
        isSimulating = false
        matcher = nil
        maneuvers = nil
        progress = nil
        isOffRoute = false
        if state == .navigating || state == .arrived {
            state = .idle
            routes = []
            destination = nil
        }
    }

    private func install(_ route: Route) {
        matcher = MapMatcher(route: route)
        maneuvers = ManeuverEngine(route: route)
    }

    /// Новый фикс GPS (настоящий или симулированный).
    func ingest(_ location: CLLocation) {
        lastLocation = location
        speed = max(0, location.speed)
        if location.course >= 0 { course = location.course }
        position = location.coordinate

        guard state == .navigating, var matcher, var maneuvers, let route = selectedRoute else { return }
        guard let match = matcher.match(location) else { return }
        self.matcher = matcher

        let onRoute = match.offset <= rerouteSettings.offRouteDistance
        if onRoute {
            position = match.coordinate
            if speed < 2 || location.course < 0 { course = match.routeBearing }
        }
        let progress = maneuvers.progress(distanceAlong: match.distanceAlong)
        self.progress = progress
        speedLimit = route.speedLimit(at: match.distanceAlong)

        if let announcement = maneuvers.announcement(for: progress, speed: speed) {
            lastAnnouncement = announcement
            if announcement.maneuver.kind != .arrive {
                onEvent?(.maneuver(kind: announcement.maneuver.kind, stage: announcement.stage,
                                   roundaboutExit: announcement.maneuver.roundaboutExit))
            }
        }
        self.maneuvers = maneuvers

        for event in monitor.update(speed: speed, accuracy: location.horizontalAccuracy, limit: speedLimit,
                                    distanceToManeuver: progress.distanceToManeuver,
                                    maneuverID: progress.nextManeuver?.id, now: location.timestamp) {
            onEvent?(event)
        }

        if progress.remainingDistance < 25, !arrivalAnnounced {
            arrivalAnnounced = true
            state = .arrived
            onEvent?(.arrived)
            simulationTask?.cancel()
            isSimulating = false
            return
        }

        isOffRoute = !onRoute
        if reroute.update(offset: match.offset, accuracy: location.horizontalAccuracy, at: location.timestamp) {
            Task { await self.performReroute(from: location) }
        }
    }

    @MainActor
    private func performReroute(from location: CLLocation) async {
        guard !isRerouting, let destination, let engine = engineProvider() else { return }
        isRerouting = true
        defer { isRerouting = false }
        let started = Date()
        do {
            let heading = location.course >= 0 ? location.course : nil
            let fresh = try await engine.routes(from: location.coordinate, heading: heading, to: destination.coordinate,
                                                mode: mode, alternatives: 0)
            guard state == .navigating, let route = fresh.first else { return }
            routes = [route]
            selectedRouteIndex = 0
            install(route)
            isOffRoute = false
            onEvent?(.reroute)
            log.info("Reroute in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s")
            ingest(location)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Симуляция (меню отладки)

    /// Проехать выбранный маршрут с постоянной скоростью.
    func simulateRoute(speedKmh: Double) {
        if state == .previewing { start() }
        guard let route = selectedRoute else { return }
        runSimulation(TrackSimulator(route: route, speed: speedKmh / 3.6))
    }

    /// Проиграть GPX: точки трека как есть, по одной в секунду.
    func simulateGPX(_ data: Data, speedKmh: Double = 50) {
        let points = GPXParser.parse(data)
        guard points.count >= 2 else {
            lastError = "В GPX нет точек трека."
            return
        }
        runSimulation(TrackSimulator(coordinates: points.map(\.coordinate), speed: speedKmh / 3.6))
    }

    private func runSimulation(_ simulator: TrackSimulator) {
        simulationTask?.cancel()
        isSimulating = true
        simulationTask = Task { @MainActor [weak self] in
            var sim = simulator
            while !Task.isCancelled, !sim.isFinished {
                guard let fix = sim.advance(by: 1) else { break }
                self?.ingest(fix)
                try? await Task.sleep(for: .seconds(1))
            }
            self?.isSimulating = false
        }
    }
}

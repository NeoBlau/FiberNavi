import XCTest
import CoreLocation
@testable import FiberNavi

/// Тестовый маршрут: 1 км на восток по Тверской широте, поворот налево, 500 м на север.
enum Fixtures {
    static let start = CLLocationCoordinate2D(latitude: 55.75, longitude: 37.60)

    static func offset(_ base: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        let dLat = north / Geo.earthRadius * 180 / .pi
        let dLon = east / (Geo.earthRadius * cos(base.latitude * .pi / 180)) * 180 / .pi
        return CLLocationCoordinate2D(latitude: base.latitude + dLat, longitude: base.longitude + dLon)
    }

    static var route: Route {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...10 { coords.append(offset(start, east: Double(i) * 100, north: 0)) }
        let corner = coords.last!
        for i in 1...5 { coords.append(offset(corner, east: 0, north: Double(i) * 100)) }
        let draft = Route(coordinates: coords, maneuvers: [], duration: 120)
        let maneuvers = [
            Maneuver(id: 0, kind: .depart, instruction: "Drive east.", streetNames: [], beginShapeIndex: 0,
                     distanceFromStart: 0, length: 1000, duration: 72, roundaboutExit: nil, lanes: []),
            Maneuver(id: 1, kind: .left, instruction: "Turn left.", streetNames: ["Тверская"], beginShapeIndex: 10,
                     distanceFromStart: draft.cumulative[10], length: 500, duration: 48, roundaboutExit: nil, lanes: []),
            Maneuver(id: 2, kind: .arrive, instruction: "You have arrived.", streetNames: [], beginShapeIndex: 15,
                     distanceFromStart: draft.cumulative[15], length: 0, duration: 0, roundaboutExit: nil, lanes: []),
        ]
        return Route(coordinates: coords, maneuvers: maneuvers, duration: 120,
                     speedLimits: [SpeedLimitSpan(startDistance: 0, endDistance: 1000, limit: 60)])
    }

    static func fix(_ c: CLLocationCoordinate2D, speed: Double = 16.7, course: Double = 90, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: c, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: course, courseAccuracy: 5, speed: speed, speedAccuracy: 1, timestamp: Date())
    }
}

final class GeoTests: XCTestCase {
    func testPolylineRoundTrip() {
        let coords = [CLLocationCoordinate2D(latitude: 55.751244, longitude: 37.618423),
                      CLLocationCoordinate2D(latitude: 55.972641, longitude: 37.414589),
                      CLLocationCoordinate2D(latitude: -33.5, longitude: -70.25)]
        let decoded = Polyline.decode(Polyline.encode(coords))
        XCTAssertEqual(decoded.count, 3)
        for (a, b) in zip(coords, decoded) {
            XCTAssertEqual(a.latitude, b.latitude, accuracy: 1e-6)
            XCTAssertEqual(a.longitude, b.longitude, accuracy: 1e-6)
        }
    }

    func testDistanceKremlinToSheremetyevo() {
        let d = Geo.distance(CLLocationCoordinate2D(latitude: 55.7520, longitude: 37.6175),
                             CLLocationCoordinate2D(latitude: 55.9726, longitude: 37.4146))
        XCTAssertEqual(d, 27_604, accuracy: 50)
    }

    func testRouteGeometry() {
        let route = Fixtures.route
        XCTAssertEqual(route.distance, 1500, accuracy: 2)
        XCTAssertEqual(route.bearing(at: 500), 90, accuracy: 1)
        XCTAssertEqual(route.bearing(at: 1300), 0, accuracy: 1)
        XCTAssertEqual(route.speedLimit(at: 400), 60)
        XCTAssertNil(route.speedLimit(at: 1200))
    }
}

final class MapMatcherTests: XCTestCase {
    func testSnapsToRouteWithOffset() throws {
        var matcher = MapMatcher(route: Fixtures.route)
        let p = Fixtures.offset(Fixtures.start, east: 350, north: 12)
        let m = try XCTUnwrap(matcher.match(Fixtures.fix(p)))
        XCTAssertEqual(m.distanceAlong, 350, accuracy: 2)
        XCTAssertEqual(m.offset, 12, accuracy: 1)
        XCTAssertEqual(m.segmentIndex, 3)
    }

    func testHeadingPicksCorrectLegNearCorner() throws {
        // Точка у угла, но движемся на север — должна привязаться ко второму плечу.
        var matcher = MapMatcher(route: Fixtures.route)
        let corner = Fixtures.offset(Fixtures.start, east: 1000, north: 0)
        let p = Fixtures.offset(corner, east: 4, north: 6)
        let m = try XCTUnwrap(matcher.match(Fixtures.fix(p, course: 0)))
        XCTAssertGreaterThanOrEqual(m.segmentIndex, 10)
    }

    func testFarPointHasLargeOffset() throws {
        var matcher = MapMatcher(route: Fixtures.route)
        let p = Fixtures.offset(Fixtures.start, east: 500, north: -200)
        let m = try XCTUnwrap(matcher.match(Fixtures.fix(p)))
        XCTAssertEqual(m.offset, 200, accuracy: 2)
    }
}

final class ManeuverEngineTests: XCTestCase {
    func testProgressAndNextManeuver() {
        let engine = ManeuverEngine(route: Fixtures.route)
        let p = engine.progress(distanceAlong: 300)
        XCTAssertEqual(p.nextManeuver?.kind, .left)
        XCTAssertEqual(p.distanceToManeuver, 700, accuracy: 2)
        XCTAssertEqual(p.remainingDistance, 1200, accuracy: 2)
        XCTAssertEqual(p.remainingTime, 96, accuracy: 1)
        XCTAssertEqual(p.maneuverAfter?.kind, .arrive)
    }

    func testCityAt60AnnouncesNoLaterThan150m() {
        // Критерий ТЗ: инструкция не позже чем за 150 м в городе на 60 км/ч.
        var engine = ManeuverEngine(route: Fixtures.route)
        let speed = 60 / 3.6
        var stages: [(AnnouncementStage, Double)] = []
        var along = 0.0
        while along < 1000 {
            let p = engine.progress(distanceAlong: along)
            if let a = engine.announcement(for: p, speed: speed), a.maneuver.kind == .left {
                stages.append((a.stage, a.distance))
            }
            along += speed // фикс раз в секунду
        }
        XCTAssertEqual(stages.map(\.0), [.far, .near, .now])
        let near = stages.first { $0.0 == .near }!
        XCTAssertGreaterThanOrEqual(near.1, 150)
    }

    func testEachStageOnceAndSkipsPassedStages() {
        var engine = ManeuverEngine(route: Fixtures.route)
        // Старт сразу в 100 м от поворота — звучит только ближний этап.
        let p = engine.progress(distanceAlong: 900)
        let first = engine.announcement(for: p, speed: 10)
        XCTAssertEqual(first?.stage, .near)
        XCTAssertNil(engine.announcement(for: p, speed: 10))
        let p2 = engine.progress(distanceAlong: 970)
        XCTAssertEqual(engine.announcement(for: p2, speed: 10)?.stage, .now)
        XCTAssertNil(engine.announcement(for: engine.progress(distanceAlong: 975), speed: 10))
    }

    func testHighwayFarThresholdIsLonger() {
        let engine = ManeuverEngine(route: Fixtures.route)
        XCTAssertEqual(engine.threshold(for: .far, speed: 100 / 3.6), 1000)
        XCTAssertEqual(engine.threshold(for: .far, speed: 50 / 3.6), 500)
        XCTAssertEqual(engine.threshold(for: .near, speed: 110 / 3.6), 110 / 3.6 * 12, accuracy: 0.1)
    }
}

final class RerouteServiceTests: XCTestCase {
    func testNeedsSustainedOffsetAndRespectsCooldown() {
        var service = RerouteService()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0))
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(2)))
        XCTAssertTrue(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(4)))
        // Сразу после перестроения — кулдаун.
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(5)))
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(9)))
        XCTAssertTrue(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(14.5)))
    }

    func testReturnToRouteResetsAndBadAccuracyIgnored() {
        var service = RerouteService()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = service.update(offset: 80, accuracy: 10, at: t0)
        XCTAssertFalse(service.update(offset: 5, accuracy: 10, at: t0.addingTimeInterval(3)))
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(5)))
        XCTAssertFalse(service.update(offset: 80, accuracy: 10, at: t0.addingTimeInterval(8)))
        XCTAssertFalse(service.update(offset: 500, accuracy: 120, at: t0.addingTimeInterval(20)))
    }
}

final class DrivingMonitorTests: XCTestCase {
    func testSpeedingRepeatsOncePerMinute() {
        var monitor = DrivingMonitor()
        let t0 = Date(timeIntervalSince1970: 0)
        let fast = 80 / 3.6
        XCTAssertEqual(monitor.update(speed: fast, accuracy: 5, limit: 60, distanceToManeuver: 100, maneuverID: 1, now: t0),
                       [.speeding(limit: 60)])
        XCTAssertEqual(monitor.update(speed: fast, accuracy: 5, limit: 60, distanceToManeuver: 100, maneuverID: 1,
                                      now: t0.addingTimeInterval(30)), [])
        XCTAssertEqual(monitor.update(speed: fast, accuracy: 5, limit: 60, distanceToManeuver: 100, maneuverID: 1,
                                      now: t0.addingTimeInterval(61)), [.speeding(limit: 60)])
    }

    func testTrafficJamAfterTwoMinutesSlowOnFastRoad() {
        var monitor = DrivingMonitor()
        let t0 = Date(timeIntervalSince1970: 0)
        var events: [GuidanceEvent] = []
        for s in stride(from: 0.0, through: 130, by: 5) {
            events += monitor.update(speed: 5 / 3.6, accuracy: 5, limit: 80, distanceToManeuver: 300, maneuverID: 1,
                                     now: t0.addingTimeInterval(s))
        }
        XCTAssertEqual(events.filter { $0 == .trafficJam }.count, 1)
    }

    func testLongStraightOncePerManeuver() {
        var monitor = DrivingMonitor()
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(monitor.update(speed: 25, accuracy: 5, limit: 110, distanceToManeuver: 8000, maneuverID: 4, now: t0),
                       [.longStraight])
        XCTAssertEqual(monitor.update(speed: 25, accuracy: 5, limit: 110, distanceToManeuver: 7900, maneuverID: 4,
                                      now: t0.addingTimeInterval(4)), [])
    }
}

final class SimulationTests: XCTestCase {
    func testGPXParse() {
        let gpx = """
        <?xml version="1.0"?><gpx version="1.1"><trk><trkseg>
        <trkpt lat="55.75" lon="37.60"><time>2026-10-27T10:00:00Z</time></trkpt>
        <trkpt lat="55.76" lon="37.61"><time>2026-10-27T10:00:05Z</time></trkpt>
        </trkseg></trk></gpx>
        """
        let points = GPXParser.parse(Data(gpx.utf8))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].coordinate.latitude, 55.76, accuracy: 1e-9)
        XCTAssertEqual(points[1].timestamp.timeIntervalSince(points[0].timestamp), 5)
    }

    func testSimulatorDrivesWholeRoute() {
        var sim = TrackSimulator(route: Fixtures.route, speed: 20)
        var last: CLLocation?
        var steps = 0
        while !sim.isFinished && steps < 1000 {
            last = sim.advance(by: 1)
            steps += 1
        }
        XCTAssertEqual(steps, Int((sim.length / 20).rounded(.up)))
        let end = Fixtures.route.coordinates.last!
        XCTAssertLessThan(Geo.distance(last!.coordinate, end), 1)
    }
}

final class ValhallaParsingTests: XCTestCase {
    func testParsesTripWithAlternates() throws {
        // В полилинии может встретиться обратный слэш — экранируем для JSON.
        let shape = Polyline.encode(Fixtures.route.coordinates).replacingOccurrences(of: "\\", with: "\\\\")
        let json = """
        {"trip":{"legs":[{"shape":"\(shape)","summary":{"time":120,"length":1.5},
          "maneuvers":[{"type":1,"instruction":"Drive east.","begin_shape_index":0,"length":1.0,"time":72},
                       {"type":15,"instruction":"Turn left onto Тверская.","street_names":["Тверская"],"begin_shape_index":10,"length":0.5,"time":48},
                       {"type":4,"instruction":"You have arrived.","begin_shape_index":15,"length":0,"time":0}]}]},
         "alternates":[{"trip":{"legs":[{"shape":"\(shape)","summary":{"time":150},"maneuvers":[]}]}}]}
        """
        let routes = try ValhallaClient.parseRoutes(Data(json.utf8))
        XCTAssertEqual(routes.count, 2)
        let main = routes[0]
        XCTAssertEqual(main.maneuvers.map(\.kind), [.depart, .left, .arrive])
        XCTAssertEqual(main.maneuvers[1].distanceFromStart, 1000, accuracy: 2)
        XCTAssertEqual(main.maneuvers[1].streetNames, ["Тверская"])
        XCTAssertEqual(main.duration, 120)
        XCTAssertEqual(routes[1].duration, 150)
    }

    func testParsesSpeedLimitsAndMergesSpans() {
        let route = Fixtures.route
        let json = """
        {"edges":[{"speed_limit":60,"begin_shape_index":0,"end_shape_index":5},
                  {"speed_limit":60,"begin_shape_index":5,"end_shape_index":10},
                  {"speed_limit":0,"begin_shape_index":10,"end_shape_index":12},
                  {"speed_limit":40,"begin_shape_index":12,"end_shape_index":15}]}
        """
        let spans = ValhallaClient.parseSpeedLimits(Data(json.utf8), route: route)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].limit, 60)
        XCTAssertEqual(spans[0].endDistance, 1000, accuracy: 2)
        XCTAssertEqual(spans[1].limit, 40)
    }
}

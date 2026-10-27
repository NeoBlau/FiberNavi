import XCTest
import CoreLocation
@testable import FiberNavi

/// Плеер без звука: запоминает реплики и сразу «доигрывает», либо держит до ручного finish.
final class FakeVoicePlayer: VoicePlayer {
    var played: [VoiceUtterance] = []
    var stops = 0
    var autoComplete = true
    private var pending: (() -> Void)?

    func play(_ utterance: VoiceUtterance, completion: @escaping () -> Void) {
        played.append(utterance)
        if autoComplete { completion() } else { pending = completion }
    }

    func stop() {
        stops += 1
        pending = nil
    }

    func finish() {
        let done = pending
        pending = nil
        done?()
    }
}

enum VoiceFixtures {
    static func line(_ id: String, _ events: [String], explicit: Int = 0, time: String? = nil) -> VoiceManifest.Line {
        VoiceManifest.Line(id: id, file: "\(id).wav", text: id, events: events, mood: nil, weight: 1, explicit: explicit,
                           conditions: time.map { VoiceManifest.Conditions(time: $0) })
    }

    static var manifest: VoiceManifest {
        VoiceManifest(
            character: "cj", version: 1,
            lines: [
                line("start", ["route_start", "confirm"]),
                line("left_a", ["turn_left"]),
                line("arr", ["arrived"]),
                line("chat1", ["long_straight"]),
                line("chat2", ["long_straight"], explicit: 2),
                line("night", ["night_driving"], time: "night"),
                line("ok", ["confirm"]),
                line("slow", ["speeding"]),
            ],
            words: [
                "turn": [.init(file: "words/turn_01.wav", score: 0.9), .init(file: "words/turn_02.wav", score: 0.85)],
                "right": [.init(file: "words/right_01.wav", score: 0.8)],
                "now": [.init(file: "words/now_01.wav", score: 0.7, rejected: true)],
                "up_ahead": [.init(file: "words/up_ahead_01.wav", score: 0.8)],
            ],
            templates: nil)
    }

    static func bank() -> PhraseBank {
        PhraseBank(manifest: manifest, baseURL: URL(fileURLWithPath: "/voice/cj"), seed: 1)
    }

    static func context(_ t: TimeInterval = 0, night: Bool = false, profanity: VoiceSettings.Profanity = .off) -> PhraseBank.Context {
        PhraseBank.Context(now: Date(timeIntervalSince1970: t), isNight: night, speed: 50, profanity: profanity)
    }
}

final class PhraseBankTests: XCTestCase {
    func testWholeLineBeatsStitchingAndFallsBackToBaseEvent() {
        let bank = VoiceFixtures.bank()
        let u = bank.utterance(for: .maneuver(kind: .left, stage: .near, roundaboutExit: nil), context: VoiceFixtures.context())
        XCTAssertEqual(u?.source, .line(id: "left_a"))
        XCTAssertEqual(u?.priority, .instruction)
        XCTAssertEqual(u?.files.first?.lastPathComponent, "left_a.wav")
    }

    func testInstructionMayRepeatLine() {
        let bank = VoiceFixtures.bank()
        let event = GuidanceEvent.maneuver(kind: .left, stage: .now, roundaboutExit: nil)
        _ = bank.utterance(for: event, context: VoiceFixtures.context(0))
        XCTAssertEqual(bank.utterance(for: event, context: VoiceFixtures.context(60))?.source, .line(id: "left_a"))
    }

    func testStitchesWordsWhenNoLine() {
        let bank = VoiceFixtures.bank()
        let near = bank.utterance(for: .maneuver(kind: .right, stage: .near, roundaboutExit: nil), context: VoiceFixtures.context())
        XCTAssertEqual(near?.source, .stitched(words: ["turn", "right"]))
        XCTAssertEqual(near?.files.map(\.lastPathComponent), ["turn_01.wav", "right_01.wav"])
        // Следующая склейка берёт второй дубль «turn», если он почти так же хорош.
        let again = bank.utterance(for: .maneuver(kind: .right, stage: .near, roundaboutExit: nil), context: VoiceFixtures.context(5))
        XCTAssertEqual(again?.files.first?.lastPathComponent, "turn_02.wav")
        // «up ahead turn right» для дальнего этапа.
        let far = bank.utterance(for: .maneuver(kind: .right, stage: .far, roundaboutExit: nil), context: VoiceFixtures.context(9))
        XCTAssertEqual(far?.source, .stitched(words: ["up_ahead", "turn", "right"]))
    }

    func testRejectedTakeIsNotUsedAndFallsBackToLayer3() {
        // «now right» требует now (забракован) → «turn right now» тоже нет → «right».
        let bank = VoiceFixtures.bank()
        let now = bank.utterance(for: .maneuver(kind: .right, stage: .now, roundaboutExit: nil), context: VoiceFixtures.context())
        XCTAssertEqual(now?.source, .stitched(words: ["right"]))
        // Разворот: ни реплики, ни слов → UI-звук + подтверждение героя.
        let uturn = bank.utterance(for: .maneuver(kind: .uturn, stage: .near, roundaboutExit: nil), context: VoiceFixtures.context())
        guard case .fallback(let confirm)? = uturn?.source else { return XCTFail("expected fallback") }
        XCTAssertNotNil(confirm)
    }

    func testChatterAntiRepeatTwentyMinutesAndProfanityFilter() {
        let bank = VoiceFixtures.bank()
        let strict = VoiceFixtures.context(0, profanity: .strict)
        XCTAssertEqual(bank.utterance(for: .longStraight, context: strict)?.source, .line(id: "chat1"))
        // chat2 с матом запрещён, chat1 ещё «свежий» — тишина.
        XCTAssertNil(bank.utterance(for: .longStraight, context: VoiceFixtures.context(600, profanity: .strict)))
        // Через 20 минут chat1 снова доступен.
        XCTAssertEqual(bank.utterance(for: .longStraight, context: VoiceFixtures.context(1201, profanity: .strict))?.source,
                       .line(id: "chat1"))
    }

    func testTimeOfDayCondition() {
        let bank = VoiceFixtures.bank()
        XCTAssertNil(bank.utterance(for: .nightDriving, context: VoiceFixtures.context(night: false)))
        XCTAssertEqual(bank.utterance(for: .nightDriving, context: VoiceFixtures.context(night: true))?.source, .line(id: "night"))
    }

    func testFallbackKeys() {
        XCTAssertEqual(PhraseBank.fallbackKeys(for: "turn_left_near"), ["turn_left_near", "turn_left"])
        XCTAssertEqual(PhraseBank.fallbackKeys(for: "arrived"), ["arrived"])
    }
}

final class VoiceDirectorTests: XCTestCase {
    private func makeDirector(_ player: FakeVoicePlayer, defaults: UserDefaults? = nil) -> VoiceDirector {
        let suite = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        let director = VoiceDirector(player: player, settings: VoiceSettings(defaults: suite))
        director.bank = VoiceFixtures.bank()
        return director
    }

    func testInstructionCutsChatterButChatterNeverInterrupts() {
        let player = FakeVoicePlayer()
        player.autoComplete = false
        let director = makeDirector(player)
        director.handle(.longStraight)
        XCTAssertEqual(director.current?.priority, .chatter)

        director.handle(.maneuver(kind: .left, stage: .near, roundaboutExit: nil))
        XCTAssertEqual(player.stops, 1, "chatter must be cut")
        XCTAssertEqual(director.current?.priority, .instruction)

        // Пока звучит инструкция, болтовня не встаёт ни поверх, ни в очередь.
        director.handle(.trafficJam)
        director.handle(.longStop)
        XCTAssertTrue(director.queue.isEmpty)
        XCTAssertEqual(player.played.count, 2)
    }

    func testQueueOrderInstructionThenRerouteThenWarning() {
        let player = FakeVoicePlayer()
        player.autoComplete = false
        let director = makeDirector(player)
        director.handle(.maneuver(kind: .left, stage: .far, roundaboutExit: nil))
        director.handle(.speeding(limit: 60))
        director.handle(.reroute)
        director.handle(.maneuver(kind: .right, stage: .near, roundaboutExit: nil))
        XCTAssertEqual(director.queue.map(\.priority), [.instruction, .reroute, .warning])
        player.finish()
        XCTAssertEqual(director.current?.eventKey, "turn_right_near")
        player.finish()
        XCTAssertEqual(director.current?.eventKey, "reroute")
    }

    func testInstructionsOnlyAndChatterInterval() {
        let player = FakeVoicePlayer()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let director = makeDirector(player, defaults: defaults)
        var t = Date(timeIntervalSince1970: 0)
        director.now = { t }
        director.handle(.longStraight)
        t = t.addingTimeInterval(60)
        director.handle(.longStraight) // слишком рано для «обычной» частоты (5 мин)
        XCTAssertEqual(player.played.count, 1)

        director.settings.instructionsOnly = true
        t = t.addingTimeInterval(3600)
        director.handle(.longStraight)
        XCTAssertEqual(player.played.count, 1)
    }

    func testNoVoicePackStillGivesInstructionFallback() {
        let player = FakeVoicePlayer()
        let director = makeDirector(player)
        director.bank = nil
        var beeps = 0
        director.playFallbackSound = { beeps += 1 }
        director.handle(.maneuver(kind: .left, stage: .now, roundaboutExit: nil))
        director.handle(.longStraight)
        XCTAssertEqual(beeps, 1)
        XCTAssertNotNil(director.lastFallbackAt)
        XCTAssertTrue(player.played.isEmpty)
        XCTAssertNil(director.current)
    }
}

/// Сквозной прогон: маршрут → симуляция поездки на 60 км/ч → навигация → очередь фраз.
final class GuidanceRunTests: XCTestCase {
    struct FixedEngine: RoutingEngine {
        func routes(from origin: CLLocationCoordinate2D, heading: Double?, to destination: CLLocationCoordinate2D,
                    mode: TravelMode, alternatives: Int) async throws -> [Route] {
            [Fixtures.route]
        }
    }

    @MainActor
    func testSimulatedDriveProducesExpectedPhraseQueue() async {
        let session = NavigationSession(engineProvider: { FixedEngine() })
        let player = FakeVoicePlayer()
        let director = VoiceDirector(player: player, settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        director.bank = VoiceFixtures.bank()
        session.onEvent = { director.handle($0) }

        let end = Fixtures.route.coordinates.last!
        await session.plan(to: Place(id: "x", name: "Финиш", subtitle: "", latitude: end.latitude, longitude: end.longitude),
                           from: nil)
        XCTAssertEqual(session.state, .previewing)
        session.start()

        var sim = TrackSimulator(route: Fixtures.route, speed: 60 / 3.6)
        var t = Date(timeIntervalSince1970: 0)
        while !sim.isFinished, session.state == .navigating {
            t = t.addingTimeInterval(1)
            if let fix = sim.advance(by: 1, at: t) { session.ingest(fix) }
        }

        XCTAssertEqual(session.state, .arrived)
        XCTAssertEqual(director.log, [
            "chatter route_start line:start",
            "instruction turn_left_far line:left_a",
            "instruction turn_left_near line:left_a",
            "instruction turn_left_now line:left_a",
            "instruction arrived line:arr",
        ])
    }
}

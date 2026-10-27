import XCTest
import UIKit
import CoreLocation
@testable import FiberNavi

final class SolarCalculatorTests: XCTestCase {
    private let moscow = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)

    private func utc(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: string)!
    }

    func testSummerNoonIsHighDay() {
        // Местный полдень в Москве ≈ 09:30 UTC, в день солнцестояния высота ≈ 57.7°.
        let elevation = SolarCalculator.elevation(at: moscow, date: utc("2026-06-21T09:30:00Z"))
        XCTAssertEqual(elevation, 57.7, accuracy: 1.0)
        XCTAssertFalse(SolarCalculator.isNight(at: moscow, date: utc("2026-06-21T09:30:00Z")))
    }

    func testWinterMidnightIsNight() {
        XCTAssertTrue(SolarCalculator.isNight(at: moscow, date: utc("2026-12-21T21:00:00Z")))
    }

    func testWinterNoonIsLowDay() {
        // 21 декабря полуденная высота ≈ 10.8°.
        let elevation = SolarCalculator.elevation(at: moscow, date: utc("2026-12-21T09:30:00Z"))
        XCTAssertEqual(elevation, 10.8, accuracy: 1.0)
    }
}

final class StyleCompilerTests: XCTestCase {
    func testPatchReplacesTileSource() throws {
        let style = #"{"version":8,"sources":{"openmaptiles":{"type":"vector","url":"https://a"}},"layers":[]}"#
        let out = try StyleCompiler.patch(styleData: Data(style.utf8), tilesURL: URL(string: "http://home:8080/moscow.json")!)
        let json = try JSONSerialization.jsonObject(with: out) as! [String: Any]
        let source = (json["sources"] as! [String: Any])["openmaptiles"] as! [String: Any]
        XCTAssertEqual(source["url"] as? String, "http://home:8080/moscow.json")
        XCTAssertEqual(source["type"] as? String, "vector")
    }

    func testEveryThemeHasBundledDayAndNightStyles() {
        for theme in ThemeID.allCases {
            for variant in ["day", "night"] {
                XCTAssertNotNil(Bundle.main.url(forResource: "\(theme.rawValue).\(variant)", withExtension: "json"),
                                "\(theme.rawValue).\(variant).json missing from bundle")
            }
        }
    }

    /// Все `icon-image` из стилей должны быть в BlipCatalog, иначе метка не отрисуется.
    func testStyleIconsAreCoveredByCatalog() throws {
        let known = Set(BlipCatalog.keys)
        for theme in ThemeID.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "\(theme.rawValue).day", withExtension: "json"))
            let text = try String(contentsOf: url, encoding: .utf8)
            let regex = try NSRegularExpression(pattern: #""(blip\.[a-z_]+)""#)
            let names = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
            XCTAssertFalse(names.isEmpty)
            for name in names {
                XCTAssertTrue(known.contains(name), "\(theme.rawValue): \(name) not in BlipCatalog")
            }
        }
    }
}

final class UserPackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("blip"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sfx"), withIntermediateDirectories: true)
        let manifest = """
        {"theme":"gta5","version":1,"_comment":"x",
         "blips":{"blip.food":"blip/food.png","blip.atm":"blip/atm.svg","blip.parking":"blip/none.png"},
         "sounds":{"_comment":"y","ui.waypoint":"sfx/waypoint.ogg"},
         "voice":{"_comment":"z","characters":{"franklin":"voice/franklin/voice_manifest.json"}}}
        """
        try Data(manifest.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in }
        try png.write(to: dir.appendingPathComponent("blip/food.png"))
        // SVG сконвертирован pack_tool в PNG рядом.
        try png.write(to: dir.appendingPathComponent("blip/atm.png"))
        // OGG без конвертации — iOS его не сыграет.
        try Data([0]).write(to: dir.appendingPathComponent("sfx/waypoint.ogg"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testResolvesFilesAndConvertedAlternatives() {
        let pack = UserPack(theme: .gta5, root: dir)
        XCTAssertTrue(pack.isInstalled)
        XCTAssertNotNil(pack.image("blip.food"))
        XCTAssertEqual(pack.url(for: "blip.atm")?.pathExtension, "png")
        XCTAssertNil(pack.url(for: "blip.parking"))
        XCTAssertNil(pack.url(for: "ui.waypoint"), "unconverted OGG must fall back to stub")
        XCTAssertNil(pack.url(for: "blip.hospital"))
        XCTAssertEqual(pack.missingKeys, ["blip.parking", "ui.waypoint"])
        XCTAssertNil(pack.manifest?.files["_comment"])
    }

    func testMissingPackUsesStubs() {
        let pack = UserPack(theme: .rdr2, root: nil)
        XCTAssertFalse(pack.isInstalled)
        XCTAssertNil(pack.image("blip.food"))
        XCTAssertTrue(pack.missingKeys.isEmpty)
    }

    func testStubBlipsRenderForEveryCatalogEntry() {
        for entry in BlipCatalog.entries {
            let image = StubArt.blip(entry, tint: .white, background: .black)
            XCTAssertEqual(image.size, CGSize(width: 48, height: 48))
        }
    }

    func testExampleManifestDecodes() throws {
        // Тот же формат, что в Assets/UserPacks/manifest.example.json (копируется в бандл).
        let url = try XCTUnwrap(Bundle.main.url(forResource: "manifest.example", withExtension: "json", subdirectory: "UserPacks"))
        let manifest = try JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: url))
        XCTAssertEqual(manifest.voice?.characters?["franklin"], "voice/franklin/voice_manifest.json")
        XCTAssertNotNil(manifest.files["blip.gas_station"])
    }
}

import XCTest
@testable import FiberNavi

final class AppConfigTests: XCTestCase {
    func testUsesStyleURLFromInfo() {
        let config = AppConfig(info: ["FNMapStyleURL": "https://example.com/style.json"])
        XCTAssertEqual(config.mapStyleURL.absoluteString, "https://example.com/style.json")
    }

    func testFallsBackWhenMissingOrInvalid() {
        XCTAssertEqual(AppConfig(info: [:]).mapStyleURL, AppConfig.fallbackStyleURL)
        XCTAssertEqual(AppConfig(info: ["FNMapStyleURL": "not a url"]).mapStyleURL, AppConfig.fallbackStyleURL)
    }

    func testBackendURLsEmptyMeansNilAndOverridesWin() {
        let info: [String: Any] = ["FNTilesURL": "", "FNValhallaURL": "http://plist:8002"]
        let config = AppConfig(info: info, overrides: ["FNValhallaURL": "http://settings:8002"])
        XCTAssertNil(config.tilesURL)
        XCTAssertEqual(config.routingURL?.absoluteString, "http://settings:8002")
        XCTAssertNil(config.searchURL)
    }
}

final class CameraControllerTests: XCTestCase {
    func testPanDisablesFollowAndRecenterRestoresPreferredMode() {
        let camera = CameraController()
        camera.userDidPan()
        XCTAssertFalse(camera.isFollowing)

        camera.northUpPreferred = true
        camera.followUser()
        XCTAssertEqual(camera.mode, .followNorthUp)
    }
}

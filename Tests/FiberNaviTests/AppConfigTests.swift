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

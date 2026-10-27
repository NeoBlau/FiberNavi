import Observation

/// Режим камеры карты. MapView синхронизирует его с MLNMapView.userTrackingMode.
@Observable
final class CameraController {
    enum Mode: Equatable {
        case free
        /// Камера следует за пользователем и поворачивается по курсу.
        case followCourse
        /// Следует за пользователем, север сверху.
        case followNorthUp
    }

    var mode: Mode = .followCourse
    var northUpPreferred = false

    var isFollowing: Bool { mode != .free }

    func followUser() {
        mode = northUpPreferred ? .followNorthUp : .followCourse
    }

    /// Пользователь сдвинул карту жестом.
    func userDidPan() {
        mode = .free
    }
}

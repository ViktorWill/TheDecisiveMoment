import CoreLocation
import Foundation
import Observation

/// The device's heading, used to pre-fill a dropped pin's `streetBearing`.
///
/// Optional in every sense: a phone without a magnetometer, or one that has not
/// settled, simply leaves the field empty rather than offering a bearing that
/// is wrong. The pin editor says which it is.
@MainActor
@Observable
public final class HeadingProvider: NSObject, CLLocationManagerDelegate {
    /// True heading in degrees clockwise from north, `nil` until a usable
    /// reading arrives.
    public private(set) var headingDegrees: Double?
    /// Accuracy in degrees, as reported. Negative means the reading is invalid.
    public private(set) var accuracyDegrees: Double?
    public private(set) var isAvailable = CLLocationManager.headingAvailable()

    /// Beyond this the compass is being disturbed — a car, a bridge, a phone
    /// case with a magnet — and a bearing taken from it would be a fiction.
    public static let usableAccuracyDegrees = 30.0

    @ObservationIgnored private let manager = CLLocationManager()

    public override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    /// A bearing worth pre-filling, or `nil`.
    public var usableHeadingDegrees: Double? {
        guard let headingDegrees, let accuracyDegrees,
              accuracyDegrees >= 0, accuracyDegrees <= Self.usableAccuracyDegrees
        else { return nil }
        return headingDegrees
    }

    public func start() {
        guard CLLocationManager.headingAvailable() else {
            isAvailable = false
            return
        }
        manager.startUpdatingHeading()
    }

    public func stop() {
        manager.stopUpdatingHeading()
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        let trueHeading = newHeading.trueHeading
        let magnetic = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            // True north where it is known; magnetic otherwise, because a street
            // bearing a few degrees out still names the right street.
            self.headingDegrees = trueHeading >= 0 ? trueHeading : magnetic
            self.accuracyDegrees = accuracy
        }
    }
}

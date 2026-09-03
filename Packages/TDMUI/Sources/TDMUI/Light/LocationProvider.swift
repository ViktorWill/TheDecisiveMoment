import CoreLocation
import Foundation
import Observation
import TDMCore

/// Where the phone is, or the best stand-in for it.
///
/// The Light screen must never block on this: sun position and the whole model
/// work from any coordinate, so an un-authorised or still-fixing device gets the
/// fallback and a marker saying so, not a spinner.
@MainActor
@Observable
public final class LocationProvider {
    /// Times Square. A fallback has to be *somewhere*, and this one is honest
    /// about being a guess because the UI labels it.
    public static let fallbackCoordinate = Coordinate(latitude: 40.7580, longitude: -73.9855)

    /// The last fix, if there has been one.
    public private(set) var fix: Coordinate?
    /// A coordinate the user chose — a spot picked on the Map tab.
    public var override: Coordinate? {
        didSet { if override != oldValue { announce() } }
    }

    /// Called when the coordinate the model should use has moved far enough to
    /// change the answer. Weather is cached per coordinate, so a fix arriving
    /// after the fallback has to invalidate it rather than sit there unused.
    @ObservationIgnored public var onCoordinateChange: (@MainActor (Coordinate) -> Void)?

    /// Below this the sun position moves by far less than the model's own
    /// resolution and the weather cache key does not change, so a new fix is not
    /// worth a recompute. Metres.
    public static let significantMoveMetres: Double = 200
    public private(set) var authorisation: CLAuthorizationStatus
    public private(set) var failed = false

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let manager = CLLocationManager()

    public init() {
        authorisation = manager.authorizationStatus
    }

    deinit {
        updates?.cancel()
    }

    /// What the model should use.
    public var coordinate: Coordinate { override ?? fix ?? Self.fallbackCoordinate }

    /// True when the coordinate is the fallback rather than a fix or a choice.
    public var isUsingFallback: Bool { override == nil && fix == nil }

    /// Starts listening. Safe to call more than once.
    public func start() {
        guard updates == nil else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    self.authorisation = self.manager.authorizationStatus
                    if let location = update.location {
                        let previous = self.coordinate
                        self.fix = Coordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                        self.failed = false
                        if Self.isSignificantMove(from: previous, to: self.coordinate) {
                            self.announce()
                        }
                    }
                }
            } catch {
                self?.failed = true
            }
        }
    }

    private func announce() {
        onCoordinateChange?(coordinate)
    }

    /// Equirectangular distance is plenty at street scale and keeps this free of
    /// a CoreLocation round trip.
    static func isSignificantMove(from: Coordinate, to: Coordinate) -> Bool {
        let metresPerDegree = 111_320.0
        let meanLatitudeRad = ((from.latitude + to.latitude) / 2) * .pi / 180
        let dx = (to.longitude - from.longitude) * metresPerDegree * cos(meanLatitudeRad)
        let dy = (to.latitude - from.latitude) * metresPerDegree
        return (dx * dx + dy * dy).squareRoot() >= significantMoveMetres
    }

    public func stop() {
        updates?.cancel()
        updates = nil
    }
}

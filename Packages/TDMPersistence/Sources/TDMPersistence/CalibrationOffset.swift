import Foundation

/// A measured correction to the model, learned from the live meter.
///
/// Per scene type rather than global: sections 2–5 of the exposure model are a
/// physical model plus a lookup table, and they will be wrong by a stop in some
/// streets. Being wrong by a *consistent* stop the user can correct once is
/// acceptable; being wrong unpredictably is not.
///
/// The scene is carried as a raw string so this package stays clear of
/// `TDMLight` — the caller passes `ScenePreset.rawValue`.
public struct CalibrationOffset: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(sceneIdentifier)|\(isArtificialLight)" }
    /// `ScenePreset.rawValue` from `TDMLight`.
    public var sceneIdentifier: String
    /// Daylight and artificial light are different errors and get different
    /// offsets, even for the same street.
    public var isArtificialLight: Bool
    /// Measured minus modelled, in stops. Added to the estimate before solving.
    public var offsetEV: Double
    public var measuredAt: Date

    public init(
        sceneIdentifier: String,
        isArtificialLight: Bool,
        offsetEV: Double,
        measuredAt: Date = Date()
    ) {
        self.sceneIdentifier = sceneIdentifier
        self.isArtificialLight = isArtificialLight
        self.offsetEV = offsetEV
        self.measuredAt = measuredAt
    }

    /// An offset beyond this is a mis-measurement, not a calibration — a lens
    /// cap, or a meter reading of a light source rather than of the scene.
    public static let maximumPlausibleEV = 3.0

    public var isPlausible: Bool { abs(offsetEV) <= Self.maximumPlausibleEV && offsetEV.isFinite }
}

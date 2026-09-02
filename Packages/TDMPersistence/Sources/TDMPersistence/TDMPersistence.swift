import Foundation
import TDMCore
import TDMSpots

/// Namespace for the persistence layer.
///
/// The SwiftData models for cached bundles, user pins, gear profiles and
/// calibration offsets — plus the bundle download/verify/import flow — land
/// here in M2.
public enum TDMPersistence {
    /// Schema version of the local SwiftData store.
    public static let storeSchemaVersion = 1
}

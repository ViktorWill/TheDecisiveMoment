import TDMCore

/// Namespace for spot handling.
///
/// Bundle decoding and integrity checking, merge/dedupe/scoring, search and the
/// `SpotStore` protocol land here in M2.
public enum TDMSpots {
    /// Bundle schema version this package can decode.
    public static let supportedBundleSchemaVersion = TDMCore.bundleSchemaVersion
}

import TDMCore

/// Namespace for spot handling.
///
/// Bundle decoding and integrity checking (``BundleDecoder``), merge and dedupe
/// (``SpotMerger``), ranking (``SpotScorer``), search and filtering
/// (``SpotFilter``), and the ``SpotStore`` protocol that `TDMPersistence`
/// implements. Ranking lives here rather than in the pipeline so a re-rank does
/// not require a data rebuild.
public enum TDMSpots {
    /// Bundle schema version this package can decode.
    public static let supportedBundleSchemaVersion = TDMCore.bundleSchemaVersion
}

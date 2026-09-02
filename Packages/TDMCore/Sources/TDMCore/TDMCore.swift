/// Namespace for package-level metadata.
///
/// The value types (`Spot`, `City`, `GearProfile`, …) described in
/// `docs/ARCHITECTURE.md` land here in M2.
public enum TDMCore {
    /// Version of the bundle schema this build reads and writes.
    ///
    /// `spotforge` links this package, so the writer and the reader cannot
    /// disagree about the schema — see `docs/DATA-BUNDLES.md`.
    public static let bundleSchemaVersion = 1
}

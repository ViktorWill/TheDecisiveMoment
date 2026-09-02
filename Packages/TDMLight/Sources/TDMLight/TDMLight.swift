import TDMCore

/// Namespace for the light model.
///
/// Solar position, the illuminance → EV100 model, the exposure solver and the
/// depth-of-field maths land here in M1, implemented against
/// `docs/EXPOSURE-MODEL.md`.
public enum TDMLight {
    /// Reference sensitivity for every EV value the package reports.
    ///
    /// EV figures are always EV100 unless a name says otherwise.
    public static let referenceISO = 100
}

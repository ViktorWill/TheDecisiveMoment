import TDMCore

/// Namespace for the light model.
///
/// The package is `docs/EXPOSURE-MODEL.md` in code: ``Solar`` (§1),
/// ``Illuminance`` (§2–§3), ``Modifiers`` (§4), ``NightPreset`` (§5),
/// ``DepthOfField`` and ``ZoneFocus`` (§6), ``ExposureSolver`` (§7–§8) and
/// ``Uncertainty`` (§9), with ``LightModel`` composing the ambient chain.
///
/// Everything here is pure, deterministic maths: no network, no Apple
/// frameworks, no clock. Angles are degrees, focal lengths and circles of
/// confusion millimetres, focus distances metres, shutter times seconds.
public enum TDMLight {
    /// Reference sensitivity for every EV value the package reports.
    ///
    /// EV figures are always EV100 unless a name says otherwise.
    public static let referenceISO = 100
}

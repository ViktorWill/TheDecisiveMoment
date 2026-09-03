import Foundation

/// Turning numbers into the sentence the user acts on.
///
/// This lives beside the maths rather than in the UI because the honesty rules
/// of `docs/SPEC-light.md` are about precision, and precision is a property of
/// the model, not of a font: **never show more precision than σ supports**, and
/// **never name a distance the lens does not have**.
public enum ExposurePhrasing {
    /// `f/8`, `f/6.7`, `f/1.4`. Half-stop clicks keep their decimal.
    public static func aperture(_ value: Double) -> String {
        "f/" + number(value, decimals: value.rounded() == value ? 0 : 1)
    }

    /// `1/250`, `1 s`, `15 s`. Seconds in, always — `1/250`, never `250`.
    public static func shutter(_ seconds: TimeInterval) -> String {
        guard seconds > 0, seconds.isFinite else { return "—" }
        if seconds >= 1 { return number(seconds, decimals: seconds.rounded() == seconds ? 0 : 1) + " s" }
        return "1/" + number((1 / seconds).rounded(), decimals: 0)
    }

    /// The shutter, hedged when the estimate cannot support the digits.
    ///
    /// Honesty rule 1: above the daylight σ the answer is a region, not a
    /// setting, and the phrasing says "about" so the user meters or brackets.
    public static func shutter(_ seconds: TimeInterval, sigmaEV: Double) -> String {
        let phrase = shutter(seconds)
        return sigmaEV > hedgeThresholdEV ? "about \(phrase)" : phrase
    }

    /// Above this σ the recommendation is hedged. 1.0 EV is the boundary between
    /// the daylight rows of §9 and the twilight and night ones.
    public static let hedgeThresholdEV = 1.0

    public static func iso(_ value: Int) -> String { "ISO \(value)" }

    /// `f/8 · 1/250 · ISO 400` — the one line the screen exists for.
    ///
    /// σ is required rather than optional: the headline is exactly the place
    /// honesty rule 1 applies, so there is no unhedged overload to reach for by
    /// accident.
    public static func setting(
        aperture f: Double,
        shutter seconds: TimeInterval,
        iso value: Int,
        sigmaEV: Double
    ) -> String {
        "\(aperture(f)) · \(shutter(seconds, sigmaEV: sigmaEV)) · \(iso(value))"
    }

    /// A distance mark as it reads on the barrel: `0.7 m`, `3 m`, `0.85 m`, `∞`.
    ///
    /// Honesty rule 4 is about the *value*, so this formatter never rounds one
    /// mark into another: it uses the fewest decimals that reproduce the mark
    /// exactly, up to ``distanceDecimalLimit``.
    public static func distance(_ metres: Double) -> String {
        guard metres.isFinite else { return "∞" }
        for decimals in 0...distanceDecimalLimit {
            let rounded = (metres * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
            if abs(rounded - metres) < 1e-9 {
                return number(metres, decimals: decimals) + " m"
            }
        }
        return number(metres, decimals: distanceDecimalLimit) + " m"
    }

    /// No lens is engraved finer than a centimetre.
    public static let distanceDecimalLimit = 2

    /// A *computed* depth-of-field limit, which is an estimate rather than an
    /// engraving and is rounded like one: `1.9 m`, `7 m`, `∞`.
    public static func sharpLimit(_ metres: Double) -> String {
        guard metres.isFinite else { return "∞" }
        let decimals = metres >= 10 || metres.rounded() == metres ? 0 : 1
        return number(metres, decimals: decimals) + " m"
    }

    /// `scale to 3 m — sharp 1.9 to 7.2 m`, or `… — sharp 1.4 m to ∞`.
    ///
    /// - Parameter markMetres: An engraved mark. Passing anything else breaks
    ///   honesty rule 4, so callers take it from the solver, never from a slider.
    public static func zoneSentence(markMetres: Double, near: Double, far: Double) -> String {
        let mark = distance(markMetres)
        if !far.isFinite {
            return "scale to \(mark) — sharp \(sharpLimit(near)) to ∞"
        }
        return "scale to \(mark) — sharp \(number(near, decimals: near >= 10 ? 0 : 1)) to \(sharpLimit(far))"
    }

    /// `EV 14.1 ± 0.5`. Honesty rule 2: the uncertainty is part of the answer.
    public static func exposureValue(_ ev100: Double, sigmaEV: Double) -> String {
        "EV \(number(ev100, decimals: 1)) ± \(number(sigmaEV, decimals: 1))"
    }

    /// `sun 14.7° · 20% cloud`, with `no weather` in place of the cloud figure
    /// when the model has fallen back to clear sky (honesty rule 3).
    public static func conditions(
        sunElevationDegrees: Double,
        cloudCover: Double?,
        isStale: Bool = false
    ) -> String {
        var parts = ["sun \(number(sunElevationDegrees, decimals: 1))°"]
        if let cloudCover {
            let percent = number((cloudCover * 100).rounded(), decimals: 0)
            parts.append(isStale ? "\(percent)% cloud (stale)" : "\(percent)% cloud")
        } else {
            parts.append("no weather — clear sky assumed")
        }
        return parts.joined(separator: " · ")
    }

    /// A signed stop difference: `+0.4 EV`, `−0.7 EV`. Uses a real minus sign.
    public static func signedStops(_ stops: Double) -> String {
        let magnitude = number(abs(stops), decimals: 1)
        return "\(stops < 0 ? "−" : "+")\(magnitude) EV"
    }

    /// `in 42 min`, `in 2 h 05`, `now`. Nothing finer than a minute: the model's
    /// event times are not better than that.
    public static func countdown(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "—" }
        if interval <= 60 { return "now" }
        let minutes = Int((interval / 60).rounded(.down))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return String(format: "in %d h %02d", hours, remainder)
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "∞" }
        // A negative zero prints as "-0.0", which looks like a bug to the reader.
        let cleaned = value == 0 ? 0 : value
        // A real minus sign: the app is read at arm's length, and a hyphen at
        // that distance is easy to miss on a negative sun elevation.
        return String(format: "%.\(decimals)f", cleaned).replacingOccurrences(of: "-", with: "−")
    }
}

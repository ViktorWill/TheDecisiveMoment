import Foundation
import TDMCore

/// The same answers, phrased for a screen reader.
///
/// The written forms are engravings — `f/8`, `1/250`, `EV 14.1 ± 0.5` — and a
/// screen reader says them as "f slash 8", "1 slash 250", "EV 14.1 plus or
/// minus 0.5" or worse. What the photographer needs to hear at arm's length,
/// walking, is the sentence a person would say. These are the spoken twins of
/// the formatters above; the numbers are identical, only the words differ.
extension ExposurePhrasing {
    /// `f 8`, `f 1.4`.
    public static func spokenAperture(_ value: Double) -> String {
        "f " + spokenNumber(value, decimals: value.rounded() == value ? 0 : 1)
    }

    /// `1 over 250 of a second`, `1 second`, `15 seconds`.
    public static func spokenShutter(_ seconds: TimeInterval) -> String {
        guard seconds > 0, seconds.isFinite else { return "no shutter speed" }
        if seconds >= 1 {
            let decimals = seconds.rounded() == seconds ? 0 : 1
            let figure = spokenNumber(seconds, decimals: decimals)
            return figure == "1" ? "1 second" : "\(figure) seconds"
        }
        return "1 over \(spokenNumber((1 / seconds).rounded(), decimals: 0)) of a second"
    }

    /// Hedged exactly where the written form hedges, honesty rule 1.
    public static func spokenShutter(_ seconds: TimeInterval, sigmaEV: Double) -> String {
        let phrase = spokenShutter(seconds)
        return sigmaEV > hedgeThresholdEV ? "about \(phrase)" : phrase
    }

    /// `f 8, 1 over 250 of a second, ISO 400` — the headline, said aloud.
    public static func spokenSetting(
        aperture f: Double,
        shutter seconds: TimeInterval,
        iso value: Int,
        sigmaEV: Double
    ) -> String {
        "\(spokenAperture(f)), \(spokenShutter(seconds, sigmaEV: sigmaEV)), \(iso(value))"
    }

    /// `plus one third of a stop`, `minus two thirds of a stop`, `no exposure
    /// compensation`. The dial clicks in thirds, so thirds is what is said.
    public static func spokenCompensation(_ stops: Double) -> String {
        let clicks = Int((stops / (1.0 / 3)).rounded())
        guard clicks != 0 else { return "no exposure compensation" }
        let magnitude = abs(clicks)
        let whole = magnitude / 3
        let thirds = magnitude % 3
        var figure = ""
        if whole > 0 { figure = whole == 1 ? "one stop" : "\(whole) stops" }
        if thirds > 0 {
            let fraction = thirds == 1 ? "one third" : "two thirds"
            figure = whole > 0 ? "\(figure) and \(fraction)" : "\(fraction) of a stop"
        }
        return "\(clicks < 0 ? "minus" : "plus") \(figure)"
    }

    /// `EV 14.1, plus or minus 0.5`.
    public static func spokenExposureValue(_ ev100: Double, sigmaEV: Double) -> String {
        "EV \(spokenNumber(ev100, decimals: 1)), plus or minus \(spokenNumber(sigmaEV, decimals: 1))"
    }

    /// `set the scale to 3 metres, sharp from 1.9 to 7.2 metres`.
    public static func spokenZoneSentence(markMetres: Double, near: Double, far: Double) -> String {
        let mark = spokenMetres(markMetres, decimals: distanceDecimals(for: markMetres))
        let nearPhrase = spokenNumber(near, decimals: near >= 10 ? 0 : 1)
        guard far.isFinite else {
            return "set the scale to \(mark), sharp from \(nearPhrase) metres to infinity"
        }
        let farPhrase = spokenMetres(far, decimals: far >= 10 || far.rounded() == far ? 0 : 1)
        return "set the scale to \(mark), sharp from \(nearPhrase) to \(farPhrase)"
    }

    /// `sun 14.7 degrees above the horizon, 20 percent cloud`, and the same
    /// honesty about a missing forecast the written line carries.
    public static func spokenConditions(
        sunElevationDegrees: Double,
        cloudCover: Double?,
        isStale: Bool = false
    ) -> String {
        let elevation = spokenNumber(abs(sunElevationDegrees), decimals: 1)
        let horizon = sunElevationDegrees < 0 ? "below" : "above"
        var parts = ["sun \(elevation) degrees \(horizon) the horizon"]
        if let cloudCover {
            let percent = spokenNumber((cloudCover * 100).rounded(), decimals: 0)
            parts.append(isStale ? "\(percent) percent cloud, stale" : "\(percent) percent cloud")
        } else {
            parts.append("no weather, clear sky assumed")
        }
        return parts.joined(separator: ", ")
    }

    private static func distanceDecimals(for metres: Double) -> Int {
        guard metres.isFinite else { return 0 }
        for decimals in 0...distanceDecimalLimit {
            let scale = pow(10, Double(decimals))
            if abs((metres * scale).rounded() / scale - metres) < 1e-9 { return decimals }
        }
        return distanceDecimalLimit
    }

    private static func spokenMetres(_ metres: Double, decimals: Int) -> String {
        guard metres.isFinite else { return "infinity" }
        let figure = spokenNumber(metres, decimals: decimals)
        return figure == "1" ? "1 metre" : "\(figure) metres"
    }

    /// Like the written formatter, but with a spoken minus: a screen reader
    /// says the typographic minus sign as nothing at all on some voices, which
    /// would turn −5° of sun into +5°.
    private static func spokenNumber(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "infinity" }
        let cleaned = value == 0 ? 0 : value
        let text = String(format: "%.\(decimals)f", cleaned)
        return text.hasPrefix("-") ? "minus " + text.dropFirst() : text
    }
}

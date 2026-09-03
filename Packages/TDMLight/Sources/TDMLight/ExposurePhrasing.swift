import Foundation
import TDMCore

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

// MARK: - Film and sensor, §7a–7d

extension ExposurePhrasing {
    /// `0.9 stops`, `1 stop`. The figure the no-solution screen leads with.
    public static func stops(_ value: Double) -> String {
        let magnitude = abs(value)
        let text = number(magnitude, decimals: abs(magnitude - magnitude.rounded()) < 0.05 ? 0 : 1)
        return text == "1" ? "1 stop" : "\(text) stops"
    }

    /// `HP5 400 @ 1600 (+2)` — what stands wherever the ISO would, on film.
    public static func loadedRoll(_ roll: LoadedRoll) -> String { roll.displayName }

    /// `Raise ISO to 1600`. On a sensor the ISO is a change the photographer
    /// makes, so it is phrased as one, §7d.
    public static func raiseISO(to value: Int) -> String { "Raise ISO to \(value)" }

    /// `f/8 · A · +1/3 EV · ISO 400` — the aperture-priority answer.
    ///
    /// No shutter speed: the body picks one steplessly, so quoting a speed
    /// would be quoting a number the photographer cannot set. What they do set
    /// is the ring and the compensation dial.
    public static func aperturePrioritySetting(
        aperture f: Double,
        compensationEV: Double,
        iso value: Int
    ) -> String {
        "\(aperture(f)) · A · \(compensation(compensationEV)) · \(iso(value))"
    }

    /// A compensation dial setting as it is engraved: `0 EV`, `+1/3 EV`,
    /// `−2/3 EV`. The dial clicks in thirds, so thirds is how it is written.
    public static func compensation(_ stops: Double) -> String {
        let clicks = Int((stops / (1.0 / 3)).rounded())
        guard clicks != 0 else { return "0 EV" }
        let sign = clicks < 0 ? "−" : "+"
        let magnitude = abs(clicks)
        let whole = magnitude / 3
        let thirds = magnitude % 3
        let figure = switch (whole, thirds) {
        case (0, _): "\(thirds)/3"
        case (_, 0): "\(whole)"
        default: "\(whole) \(thirds)/3"
        }
        return "\(sign)\(figure) EV"
    }

    /// `the body will pick about 1/180` — a prediction, not an instruction.
    public static func automaticShutter(_ seconds: TimeInterval) -> String {
        "the body will pick about \(shutter(seconds))"
    }

    /// `frames like a 47 mm`, and nothing at all on a full-frame body.
    ///
    /// Framing only: this figure must never reach the exposure or depth-of-field
    /// maths, both of which are about the lens that is actually fitted.
    public static func framing(focalLengthMillimetres f: Double, format: SensorFormat) -> String? {
        guard !format.isFullFrame else { return nil }
        let equivalent = format.equivalentFocalLengthMillimetres(f).rounded()
        return "frames like a \(number(equivalent, decimals: 0)) mm"
    }

    /// `HP5 400 is 0.9 stops short here.`
    public static func shortfallSentence(_ shortfall: ExposureShortfall, roll: LoadedRoll?) -> String {
        let subject = roll.map(loadedRoll) ?? "This gear"
        switch shortfall.sense {
        case .needsMoreLight:
            return "\(subject) is \(stops(shortfall.stops)) short here."
        case .needsLessLight:
            return "\(subject) is \(stops(shortfall.stops)) over here — there is too much light for it."
        }
    }

    /// The same sentence with the body in hand, so a sensor that has run out
    /// says so in its own terms.
    ///
    /// A digital body is not exempt from this screen: an M8 stops at ISO 2500
    /// and runs out of sensor on a dim side street exactly as a roll runs out
    /// of film, §7d — with a different set of levers, since pushing is not one
    /// of them.
    public static func shortfallSentence(
        _ shortfall: ExposureShortfall,
        body: CameraBodyProfile
    ) -> String {
        if let roll = body.loadedRoll {
            return shortfallSentence(shortfall, roll: roll)
        }
        let ceiling = body.iso.solvableValues.last
        let subject = ceiling.map { "\(body.name) at ISO \($0)" } ?? body.name
        switch shortfall.sense {
        case .needsMoreLight:
            return "\(subject) is \(stops(shortfall.stops)) short here."
        case .needsLessLight:
            return "\(subject) is \(stops(shortfall.stops)) over here — there is too much light for it."
        }
    }

    /// The headline of a lever card: what the photographer would do.
    public static func leverTitle(_ lever: ExposureLever) -> String {
        switch lever {
        case let .rate(roll, _): "Push the roll to \(roll.ratedAt)"
        case let .lowerFloor(shutter, _): "Drop to \(self.shutter(shutter))"
        case let .neutralDensity(stops): "Put on a \(stops)-stop ND"
        case let .differentRoll(isoSpeed, faster):
            "Load something \(faster ? "faster" : "slower") — ISO \(isoSpeed)"
        case let .raiseCeiling(iso): "Raise the ISO ceiling to \(iso)"
        }
    }

    /// The line under it: what it costs, in the words §7b uses.
    public static func leverDetail(_ lever: ExposureLever, floor: TimeInterval? = nil) -> String {
        switch lever {
        case let .rate(roll, _):
            let cost = roll.cost ?? "Develop the whole roll for it."
            return "\(roll.signedStops) stops · \(cost.lowercased()) · applies to the whole roll"
        case .lowerFloor:
            let floorPhrase = floor.map { "Below the \(shutter($0)) floor · " } ?? ""
            return floorPhrase + "moving subjects will smear"
        case .neutralDensity:
            return "Takes light away so the aperture you want stays on the dial"
        case .differentRoll:
            return "More than two stops short — this is the wrong film for this light"
        case .raiseCeiling:
            return "Your ceiling, not the sensor's limit — the file will be noisier"
        }
    }
}

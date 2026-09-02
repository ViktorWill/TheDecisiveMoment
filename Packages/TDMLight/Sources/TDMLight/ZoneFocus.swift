import Foundation

/// A zone-focus answer: an engraved mark, an aperture, and what that gives.
public struct ZoneFocusSetting: Sendable, Equatable {
    /// The engraved distance mark to set the barrel to, metres.
    public let markMetres: Double
    public let aperture: Double
    public let range: FocusRange

    public init(markMetres: Double, aperture: Double, range: FocusRange) {
        self.markMetres = markMetres
        self.aperture = aperture
        self.range = range
    }
}

/// Snapping the depth-of-field maths to a rangefinder barrel,
/// `docs/EXPOSURE-MODEL.md` §6.
///
/// A rangefinder lens has engraved marks and nothing in between, so every answer
/// here is reported for a mark the user can physically set. A number the user
/// cannot set is worse than useless.
public enum ZoneFocus {
    /// The sharp range for an engraved mark at an aperture.
    ///
    /// - Precondition: `markMetres` is one of the lens's engraved marks; pass
    ///   `nearestMark(to:on:)` first if you have an arbitrary distance.
    public static func range(
        lens: LensProfile,
        body: CameraBodyProfile,
        markMetres: Double,
        aperture: Double
    ) -> FocusRange {
        DepthOfField.range(
            focalLengthMillimetres: lens.focalLengthMillimetres,
            aperture: aperture,
            focusDistanceMetres: markMetres,
            circleOfConfusionMillimetres: body.circleOfConfusionMillimetres
        )
    }

    /// The engraved mark closest to a distance, in log-distance terms — the
    /// spacing of a focus scale is roughly logarithmic, so 3 m is "closer" to
    /// 2.5 m than 5 m is.
    public static func nearestMark(to distanceMetres: Double, on lens: LensProfile) -> Double? {
        let marks = lens.sortedDistanceMarks
        guard !marks.isEmpty else { return nil }
        guard distanceMetres.isFinite else { return marks.last }
        return marks.min { a, b in
            logDistance(a, from: distanceMetres) < logDistance(b, from: distanceMetres)
        }
    }

    /// The mark to set for maximum depth at an aperture: the nearest engraved
    /// mark whose far limit still runs to infinity, which is the hyperfocal
    /// setting rounded to something the barrel can express.
    public static func hyperfocalMark(
        lens: LensProfile,
        body: CameraBodyProfile,
        aperture: Double
    ) -> Double? {
        let marks = lens.sortedDistanceMarks
        for mark in marks
        where range(lens: lens, body: body, markMetres: mark, aperture: aperture).reachesInfinity {
            return mark
        }
        return marks.last
    }

    /// Given a desired sharp range, the `(mark, aperture)` that covers it,
    /// preferring the widest aperture that works so the shutter stays fast.
    ///
    /// Returns `nil` when no combination on this lens covers the range.
    public static func setting(
        covering desiredRangeMetres: ClosedRange<Double>,
        lens: LensProfile,
        body: CameraBodyProfile
    ) -> ZoneFocusSetting? {
        for aperture in lens.apertures.sorted() {
            let candidates = lens.sortedDistanceMarks
                .filter { $0 >= lens.minimumFocusMetres || !$0.isFinite }
                .map { mark in
                    ZoneFocusSetting(
                        markMetres: mark,
                        aperture: aperture,
                        range: range(lens: lens, body: body, markMetres: mark, aperture: aperture)
                    )
                }
                .filter { $0.range.covers(desiredRangeMetres) }
            // Among marks that work at this aperture, take the one with the most
            // margin at whichever end is tighter.
            if let best = candidates.max(by: { margin($0, desiredRangeMetres) < margin($1, desiredRangeMetres) }) {
                return best
            }
        }
        return nil
    }

    /// Smaller of the two margins, in log-distance, between a range and the
    /// range it has to cover.
    private static func margin(_ setting: ZoneFocusSetting, _ desired: ClosedRange<Double>) -> Double {
        let near = log(desired.lowerBound / setting.range.nearMetres)
        let far = setting.range.reachesInfinity
            ? Double.greatestFiniteMagnitude
            : log(setting.range.farMetres / desired.upperBound)
        return min(near, far)
    }

    private static func logDistance(_ mark: Double, from distanceMetres: Double) -> Double {
        guard mark.isFinite else { return .greatestFiniteMagnitude }
        return abs(log(mark) - log(distanceMetres))
    }
}

import Foundation

/// A half-open span of time, used for golden and blue hour.
///
/// `DateInterval` would do, but a plain value type keeps the package to the
/// cross-platform Foundation subset and out of any calendar semantics.
public struct TimeWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// The daily solar events derived from `Solar.position`, `docs/EXPOSURE-MODEL.md` §1.
///
/// Any of these can be `nil`: at high latitudes the sun may never cross the
/// threshold on a given day.
public struct SolarEvents: Sendable, Equatable {
    /// Apparent elevation crosses 0° upwards.
    public let sunrise: Date?
    /// Apparent elevation crosses 0° downwards.
    public let sunset: Date?
    /// Morning golden hour: elevation rising from −4° to +6°.
    public let morningGoldenHour: TimeWindow?
    /// Evening golden hour: elevation falling from +6° to −4°.
    public let eveningGoldenHour: TimeWindow?
    /// Morning blue hour: elevation rising from −6° to −4°.
    public let morningBlueHour: TimeWindow?
    /// Evening blue hour: elevation falling from −4° to −6°.
    public let eveningBlueHour: TimeWindow?

    public init(
        sunrise: Date?,
        sunset: Date?,
        morningGoldenHour: TimeWindow?,
        eveningGoldenHour: TimeWindow?,
        morningBlueHour: TimeWindow?,
        eveningBlueHour: TimeWindow?
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.morningGoldenHour = morningGoldenHour
        self.eveningGoldenHour = eveningGoldenHour
        self.morningBlueHour = morningBlueHour
        self.eveningBlueHour = eveningBlueHour
    }
}

extension Solar {
    /// Elevation thresholds the events are defined against, degrees.
    ///
    /// Sunrise and sunset use the *apparent* centre of the disc crossing the
    /// horizon: refraction is already in `Solar.position`, so no −0.833° fudge
    /// is applied here — that constant exists to approximate refraction for a
    /// geometric elevation.
    public enum ElevationThreshold {
        public static let horizon = 0.0
        public static let goldenHourUpper = 6.0
        public static let goldenHourLower = -4.0
        public static let blueHourLower = -6.0
    }

    /// The instant within `window` at which apparent elevation crosses
    /// `elevationDegrees`, found by bisection.
    ///
    /// - Parameters:
    ///   - rising: `true` for an upward crossing, `false` for a downward one.
    ///   - resolution: Bisection stops once the bracket is this short. One
    ///     second is far finer than the model's own accuracy.
    public static func crossing(
        elevationDegrees: Double,
        rising: Bool,
        in window: TimeWindow,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        coarseStep: TimeInterval = 600,
        resolution: TimeInterval = 1
    ) -> Date? {
        func offset(_ date: Date) -> Double {
            let h = Solar.elevationDegrees(
                date: date,
                latitudeDegrees: latitudeDegrees,
                longitudeDegrees: longitudeDegrees
            ) - elevationDegrees
            return rising ? h : -h
        }

        // Scan coarsely for a bracket where the offset changes from negative
        // (before the crossing) to positive (after it), then bisect it.
        var lower = window.start
        var lowerValue = offset(lower)
        while lower < window.end {
            let upper = min(lower.addingTimeInterval(coarseStep), window.end)
            let upperValue = offset(upper)
            if lowerValue <= 0, upperValue > 0 {
                return bisect(from: lower, to: upper, resolution: resolution, offset: offset)
            }
            if upper >= window.end { break }
            lower = upper
            lowerValue = upperValue
        }
        return nil
    }

    private static func bisect(
        from start: Date,
        to end: Date,
        resolution: TimeInterval,
        offset: (Date) -> Double
    ) -> Date {
        var low = start
        var high = end
        while high.timeIntervalSince(low) > resolution {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if offset(mid) <= 0 {
                low = mid
            } else {
                high = mid
            }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    /// Sunrise, sunset, golden hour and blue hour within the 24 hours starting
    /// at `dayStart`.
    ///
    /// The caller supplies the start of the local day as a UTC instant; this
    /// package deliberately knows nothing about time zones.
    public static func events(
        dayStartingAt dayStart: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> SolarEvents {
        let dayWindow = TimeWindow(start: dayStart, end: dayStart.addingTimeInterval(86_400))

        func crossing(_ elevation: Double, rising: Bool) -> Date? {
            Solar.crossing(
                elevationDegrees: elevation,
                rising: rising,
                in: dayWindow,
                latitudeDegrees: latitudeDegrees,
                longitudeDegrees: longitudeDegrees
            )
        }

        let sunrise = crossing(ElevationThreshold.horizon, rising: true)
        let sunset = crossing(ElevationThreshold.horizon, rising: false)
        let goldenLowerRising = crossing(ElevationThreshold.goldenHourLower, rising: true)
        let goldenUpperRising = crossing(ElevationThreshold.goldenHourUpper, rising: true)
        let goldenUpperFalling = crossing(ElevationThreshold.goldenHourUpper, rising: false)
        let goldenLowerFalling = crossing(ElevationThreshold.goldenHourLower, rising: false)
        let blueLowerRising = crossing(ElevationThreshold.blueHourLower, rising: true)
        let blueLowerFalling = crossing(ElevationThreshold.blueHourLower, rising: false)

        return SolarEvents(
            sunrise: sunrise,
            sunset: sunset,
            morningGoldenHour: Solar.window(from: goldenLowerRising, to: goldenUpperRising),
            eveningGoldenHour: Solar.window(from: goldenUpperFalling, to: goldenLowerFalling),
            morningBlueHour: Solar.window(from: blueLowerRising, to: goldenLowerRising),
            eveningBlueHour: Solar.window(from: goldenLowerFalling, to: blueLowerFalling)
        )
    }

    private static func window(from start: Date?, to end: Date?) -> TimeWindow? {
        guard let start, let end, end > start else { return nil }
        return TimeWindow(start: start, end: end)
    }
}

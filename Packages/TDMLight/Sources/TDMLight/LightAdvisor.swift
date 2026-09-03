import Foundation

/// Everything the Light screen knows when it asks for an answer.
///
/// One value in, one value out: the screen holds no maths, and the whole chain
/// — sun, EV, solver, zone — can be tested on Linux.
public struct AdviceRequest: Sendable, Equatable {
    public var date: Date
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    /// `nil` when there is no weather; the model then falls back to clear sky
    /// and widens σ.
    public var cloudCover: Double?
    public var weatherFreshness: WeatherFreshness
    public var precipitation: Precipitation
    public var scene: ScenePreset
    public var subjectLighting: SubjectLighting
    public var nightPreset: NightPreset
    /// The user's stored offset for this scene, from the live meter.
    public var calibrationOffsetEV: Double
    public var body: CameraBodyProfile
    public var lens: LensProfile
    public var strategy: ExposureStrategy
    public var steadiness: HandheldSteadiness
    /// A distance the user has asked for, in metres. The solver snaps it to an
    /// engraved mark; when it is `nil` the solver goes for maximum depth.
    public var subjectDistanceMetres: Double?

    public init(
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        cloudCover: Double? = nil,
        weatherFreshness: WeatherFreshness = .fresh,
        precipitation: Precipitation = .none,
        scene: ScenePreset = .openSky,
        subjectLighting: SubjectLighting = .frontLit,
        nightPreset: NightPreset = .litCommercialStreet,
        calibrationOffsetEV: Double = 0,
        body: CameraBodyProfile,
        lens: LensProfile,
        strategy: ExposureStrategy = .zoneFocus,
        steadiness: HandheldSteadiness = .standard,
        subjectDistanceMetres: Double? = nil
    ) {
        self.date = date
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.cloudCover = cloudCover
        self.weatherFreshness = weatherFreshness
        self.precipitation = precipitation
        self.scene = scene
        self.subjectLighting = subjectLighting
        self.nightPreset = nightPreset
        self.calibrationOffsetEV = calibrationOffsetEV
        self.body = body
        self.lens = lens
        self.strategy = strategy
        self.steadiness = steadiness
        self.subjectDistanceMetres = subjectDistanceMetres
    }
}

/// The answer, with everything the screen needs to explain it.
public struct Advice: Sendable, Equatable {
    public let date: Date
    public let sun: SolarPosition
    public let estimate: LightEstimate
    /// `nil` when the gear cannot expose this light; ``solverError`` says why,
    /// and the screen says that rather than showing a setting that does not work.
    public let solution: ExposureSolution?
    public let solverError: ExposureSolverError?

    public init(
        date: Date,
        sun: SolarPosition,
        estimate: LightEstimate,
        solution: ExposureSolution?,
        solverError: ExposureSolverError?
    ) {
        self.date = date
        self.sun = sun
        self.estimate = estimate
        self.solution = solution
        self.solverError = solverError
    }

    /// The engraved mark the primary answer is reported for, metres.
    public var focusMarkMetres: Double? { solution?.focusMarkMetres }

    /// Honesty rule 5: back-lit subjects are silhouettes and the model does not
    /// predict them, so there is no subject exposure to show.
    public var predictsSubjectExposure: Bool { !estimate.warnsAboutSilhouette }

    /// The setting to put at the top of the screen — `nil` when the honest
    /// answer is a warning instead.
    public var subjectSolution: ExposureSolution? {
        predictsSubjectExposure ? solution : nil
    }

    /// The same solve, when the subject is back-lit: an exposure for the
    /// *background*, offered only under that label so it cannot be mistaken for
    /// a prediction about the face.
    public var backgroundSolution: ExposureSolution? {
        predictsSubjectExposure ? nil : solution
    }
}

/// Sun → EV → setting → zone, composed once so every caller gets the same chain.
public enum LightAdvisor {
    /// The whole model for one instant.
    ///
    /// Never throws: a solver failure is part of the answer, because "your gear
    /// cannot expose this" is information the photographer needs in the street.
    public static func advise(_ request: AdviceRequest) -> Advice {
        let sun = Solar.position(
            date: request.date,
            latitudeDegrees: request.latitudeDegrees,
            longitudeDegrees: request.longitudeDegrees
        )
        let estimate = LightModel.estimate(
            LightConditions(
                sunElevationDegrees: sun.elevationDegrees,
                cloudCover: request.cloudCover,
                weatherFreshness: request.weatherFreshness,
                precipitation: request.precipitation,
                scene: request.scene,
                subjectLighting: request.subjectLighting,
                nightPreset: request.nightPreset,
                calibrationOffsetEV: request.calibrationOffsetEV
            )
        )

        let exposureRequest = ExposureRequest(
            ev100: estimate.ev100,
            body: request.body,
            lens: request.lens,
            strategy: request.strategy,
            handheldFloor: request.steadiness.floor(
                focalLengthMillimetres: request.lens.focalLengthMillimetres
            ),
            subjectDistanceMetres: request.subjectDistanceMetres
        )

        do {
            return Advice(
                date: request.date,
                sun: sun,
                estimate: estimate,
                solution: try ExposureSolver.solve(exposureRequest),
                solverError: nil
            )
        } catch let error as ExposureSolverError {
            return Advice(
                date: request.date,
                sun: sun,
                estimate: estimate,
                solution: nil,
                solverError: error
            )
        } catch {
            return Advice(
                date: request.date,
                sun: sun,
                estimate: estimate,
                solution: nil,
                solverError: .emptyGearProfile
            )
        }
    }

    /// One answer per hour, for the time scrubber.
    ///
    /// `cloudCoverForHour` returns the forecast for an hour, or `nil` where the
    /// forecast does not reach — those hours fall back to clear sky and carry
    /// the wider σ, which is what the sparkline should show.
    ///
    /// `calibrationOffsetEVForHour`, when given, is asked for each hour: an
    /// offset learned under street lamps must not be carried into the afternoon
    /// half of the same scrub.
    public static func hourly(
        from start: Date,
        hours: Int,
        request: AdviceRequest,
        calibrationOffsetEVForHour: ((Date) -> Double)? = nil,
        cloudCoverForHour: (Date) -> (cloudCover: Double?, freshness: WeatherFreshness, precipitation: Precipitation)
    ) -> [Advice] {
        guard hours > 0 else { return [] }
        return (0..<hours).map { index in
            let date = start.addingTimeInterval(Double(index) * 3_600)
            var hourly = request
            hourly.date = date
            let weather = cloudCoverForHour(date)
            hourly.cloudCover = weather.cloudCover
            hourly.weatherFreshness = weather.freshness
            hourly.precipitation = weather.precipitation
            if let calibrationOffsetEVForHour {
                hourly.calibrationOffsetEV = calibrationOffsetEVForHour(date)
            }
            return advise(hourly)
        }
    }
}

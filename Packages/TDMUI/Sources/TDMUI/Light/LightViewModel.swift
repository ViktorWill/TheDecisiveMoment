import Foundation
import Observation
import TDMCore
import TDMLight
import TDMPersistence
import TDMWeather

/// Automatic asks the solver for a setting; manual reports what a
/// photographer-chosen one does, and never refuses it. Digital only — film
/// has no solver to switch off in the first place.
public enum ExposureMode: Sendable, Equatable {
    case automatic
    case manual
}

/// The Light screen's state: inputs the user touches, and the answers that fall
/// out of them.
///
/// The maths is all in `TDMLight.LightAdvisor`; this type gathers inputs, keeps
/// the weather at arm's length, and never lets a failure stop the screen from
/// answering.
@MainActor
@Observable
public final class LightViewModel {
    /// How far ahead the scrubber can look, per `docs/SPEC-light.md`.
    public static let scrubberHours = 12

    // MARK: Inputs

    /// The bearing of the street at a spot handed over by the Map tab, degrees
    /// clockwise from north. `nil` when the user is not standing at a spot, and
    /// then the sun panel says nothing about façades rather than guessing.
    public var streetBearingDegrees: Double? {
        didSet { if streetBearingDegrees != oldValue { recompute() } }
    }

    /// Pre-filled from a selected spot's openness when the Map hands one over.
    public var scene: ScenePreset = .openSky {
        didSet { if scene != oldValue { recompute() } }
    }
    public var subjectLighting: SubjectLighting = .frontLit {
        didSet { if subjectLighting != oldValue { recompute() } }
    }
    public var nightPreset: NightPreset = .litCommercialStreet {
        didSet { if nightPreset != oldValue { recompute() } }
    }
    public var motion: SubjectMotion = .walking {
        didSet { if motion != oldValue { recompute() } }
    }
    public var steadiness: HandheldSteadiness = .standard {
        didSet { if steadiness != oldValue { recompute() } }
    }
    /// 0 is now; 1…11 look ahead an hour at a time.
    public var hourOffset: Int = 0 {
        didSet { if hourOffset != oldValue { recompute() } }
    }
    /// The mark the user dragged the barrel to. `nil` means "whatever gives the
    /// most depth", which is what the zone-focus strategy wants.
    public var chosenMarkMetres: Double? {
        didSet { if chosenMarkMetres != oldValue { recompute() } }
    }
    /// The aperture the photographer set on the lens, for a body that picks the
    /// shutter itself. `nil` everywhere else, where the app picks both.
    public var chosenAperture: Double? {
        didSet { if chosenAperture != oldValue { recompute() } }
    }

    // MARK: Manual mode
    //
    // Digital only — film is manual by nature, there is no solver to switch
    // off. None of these feed `recompute()`: manual mode never asks the
    // solver for anything, it reads the scene estimate `recompute()` already
    // keeps current and reports what a chosen aperture/shutter/ISO does with
    // it. `motion` above is shared with the freeze-motion strategy rather
    // than duplicated — "what is the subject doing" is one input, not two.

    public var mode: ExposureMode = .automatic
    /// `nil` until the photographer has picked one; manual mode starts from
    /// nothing rather than guessing a ring position for them.
    public var manualAperture: Double?
    public var manualShutter: TimeInterval?
    public var manualISO: Int?

    /// What the chosen aperture/shutter/ISO represents as a scene brightness —
    /// `ExposureSolver.measuredEV100`, the same formula the live meter reads a
    /// real exposure through, applied here to a hypothetical one instead.
    public var manualMeasuredEV100: Double? {
        guard let manualAperture, let manualShutter, let manualISO, manualShutter > 0 else { return nil }
        return ExposureSolver.measuredEV100(aperture: manualAperture, shutter: manualShutter, iso: manualISO)
    }

    /// Stops from the scene's own light — positive is under-exposed, negative
    /// is over, `Medium`'s convention. Compared against the raw scene EV100,
    /// not medium-biased `targetEV100`: manual mode is a gross-error check,
    /// and the sub-stop difference the bias makes does not change whether
    /// something is *highly* wrong.
    public var manualErrorStops: Double? {
        guard let manualMeasuredEV100, let ev100 = advice?.estimate.ev100 else { return nil }
        return manualMeasuredEV100 - ev100
    }

    /// A short, non-blocking warning — manual mode reports risk, never
    /// refuses a combination. `nil` reads as "nothing to flag", not "correct
    /// exposure": the message is deliberately about the direction of the
    /// miss, not a false claim of precision.
    public var manualExposureWarning: String? {
        guard let manualErrorStops else { return nil }
        guard !Medium.digital.latitude.accepts(errorStops: manualErrorStops) else { return nil }
        return manualErrorStops > 0
            ? "This will likely be under-exposed."
            : "This will likely be over-exposed."
    }

    /// `nil` until a shutter is chosen. `true` means the dialled shutter is at
    /// or above `motion`'s own floor for the current subject.
    public var manualFreezesMotion: Bool? {
        guard let manualShutter else { return nil }
        return manualShutter <= motion.slowestShutter
    }
    /// The sky the photographer reported, `docs/SPEC-light.md` "Sky, when there
    /// is no WeatherKit". `nil` means the forecast is in charge.
    ///
    /// In a build with no WeatherKit this is never `nil`: it is the only source
    /// of cloud cover there is. In a build with one it is an override, and an
    /// observation beats a forecast for as long as the user leaves it set.
    public private(set) var sky: SkySegment?
    /// A slower shutter the photographer has accepted, seconds, taken from the
    /// "drop to 1/30" lever on the no-solution screen. `nil` is the hold rule.
    public var acceptedFloorSeconds: TimeInterval? {
        didSet { if acceptedFloorSeconds != oldValue { recompute() } }
    }

    // MARK: State

    public private(set) var profiles: [GearProfile] = []
    /// Every body the user could put this lens on, `design/Bodies.dc.html`.
    public private(set) var bodies: [CameraBody] = []
    /// Every lens the user could put on this body — the mirror of `bodies`.
    public private(set) var lenses: [Lens] = []
    public private(set) var profile: GearProfile?
    public private(set) var advice: Advice?
    /// One answer per hour for the scrubber, starting at the current hour.
    public private(set) var hourlyAdvice: [Advice] = []
    public private(set) var events: SolarEvents?
    public private(set) var weather: WeatherReading?
    public private(set) var isRefreshing = false
    /// A tapped alternative, promoted to the top of the screen until the model
    /// next changes underneath it.
    public private(set) var promoted: ExposureRecommendation?
    /// The spot the Map handed over, when the screen is answering for one
    /// rather than for wherever the phone is.
    public private(set) var spotName: String?
    /// Offsets the live meter has taught the app, keyed by scene and light
    /// source.
    public private(set) var calibrations: [CalibrationKey: Double] = [:]

    // MARK: Dependencies

    private let weatherService: WeatherService
    private let gearStore: GearStore?
    /// Present exactly when the build has no WeatherKit, in which case it is the
    /// service's only provider and the sky control is the only weather input.
    private let manualSky: ManualWeatherProvider?
    public let location: LocationProvider
    private let clock: @MainActor () -> Date
    private var hourlyReadings: [WeatherReading] = []
    private var refreshGeneration = 0

    public init(
        weatherService: WeatherService,
        gearStore: GearStore?,
        manualSky: ManualWeatherProvider? = nil,
        location: LocationProvider = LocationProvider(),
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.weatherService = weatherService
        self.gearStore = gearStore
        self.manualSky = manualSky
        self.location = location
        self.clock = clock
        // With no forecast behind it the control is not an override, it is the
        // input — so it starts set, at whatever the provider already holds.
        self.sky = manualSky?.segment
    }

    /// Whether the sky must come from the user because nothing else can supply
    /// it. The control is then permanent rather than a tapped-open override.
    public var requiresManualSky: Bool { manualSky != nil }

    /// Takes the sky from the photographer. `nil` hands it back to the
    /// forecast, which a build with no forecast does not offer.
    public func setSky(_ segment: SkySegment?) {
        guard !(requiresManualSky && segment == nil) else { return }
        sky = segment
        if let segment { manualSky?.setSegment(segment) }
        recompute()
        // The service caches per coordinate, and the manual provider is what it
        // caches: a new segment has to reach it before the readings agree with
        // the answer on screen.
        Task { await refreshWeather(force: true) }
    }

    /// Identifies a calibration offset: a scene, in daylight or under lamps.
    public struct CalibrationKey: Hashable, Sendable {
        public let sceneIdentifier: String
        public let isArtificialLight: Bool
    }

    // MARK: Derived

    /// The instant being modelled: now, or the hour the scrubber is on.
    public var date: Date {
        Self.hourStart(of: clock()).addingTimeInterval(Double(hourOffset) * 3_600)
            .addingTimeInterval(hourOffset == 0 ? clock().timeIntervalSince(Self.hourStart(of: clock())) : 0)
    }

    public var coordinate: Coordinate { location.coordinate }

    /// The setting shown at the top: the promoted alternative, or the solver's
    /// own recommendation.
    public var recommendation: ExposureRecommendation? {
        promoted ?? advice?.solution?.primary
    }

    /// The other settings worth offering, minus whichever one is on top.
    ///
    /// Empty for a back-lit subject: offering a row of numbers there would be
    /// the pretence honesty rule 5 forbids.
    public var alternatives: [ExposureRecommendation] {
        guard let advice, advice.predictsSubjectExposure, let solution = advice.solution else { return [] }
        let all = [solution.primary] + solution.alternatives
        return Array(all.filter { $0 != recommendation }.prefix(4))
    }

    /// Whether the screen is looking at a time other than now.
    public var isScrubbing: Bool { hourOffset != 0 }

    /// The mark the answer is reported for. Always one the lens has engraved.
    public var focusMarkMetres: Double? { advice?.focusMarkMetres }

    /// The mark the barrel is drawn at: what the user dragged to, or the
    /// solver's own choice. Both come from the lens's engravings.
    public var selectedMarkMetres: Double? { chosenMarkMetres ?? focusMarkMetres }

    // MARK: Film and sensor, §7a–7d

    /// What the light lands on. The Light tab is two screens, and this is the
    /// switch, `docs/SPEC-light.md` "Two modes".
    public var medium: Medium { profile?.body.medium ?? .digital }

    /// Film mode: the ISO is a fact of the loaded roll, shown as context.
    public var isAnalog: Bool { medium.isFilm }

    public var loadedRoll: LoadedRoll? { profile?.body.loadedRoll }

    /// The highest ISO the photographer wants a file at, `nil` on film.
    public var isoCeiling: Int? { profile?.body.iso.ceiling }

    /// Every ISO the selected sensor offers, for the ceiling slider.
    public var isoLadder: [Int] { profile?.body.iso.availableValues ?? [] }

    // MARK: The body, `docs/SPEC-light.md` "The body roster"

    public var body: CameraBody? { profile?.body }

    /// Whether the camera meters at all. An M-A does not, and then the phone is
    /// the only meter in the bag, `docs/EXPOSURE-MODEL.md` §8.
    public var bodyHasMeter: Bool { body?.hasMeter ?? true }

    /// The phone meter is a cross-check on a body that meters, and the meter
    /// itself on one that does not — which is a difference in prominence, not
    /// in the measurement.
    public var isLiveMeterPrimary: Bool { !bodyHasMeter }

    /// The strategies this body can actually be set to: aperture priority is an
    /// M7 and nothing else.
    public var availableStrategies: [StoredExposureStrategy] {
        guard let body else { return StoredExposureStrategy.allCases }
        return StoredExposureStrategy.availableStrategies(on: body)
    }

    /// "frames like a 47 mm" on the M8, `nil` on a full-frame body, where there
    /// is nothing to say. Framing only: it reaches no exposure maths.
    public var framingNote: String? {
        guard let profile else { return nil }
        return ExposurePhrasing.framing(
            focalLengthMillimetres: profile.lens.focalLengthMillimetres,
            format: profile.body.format
        )
    }

    /// Why there is no setting, and what would fix it, §7b.
    public var shortfall: ExposureShortfall? { advice?.shortfall }

    /// The floor the current answer was solved against, seconds.
    public var handheldFloorSeconds: TimeInterval {
        acceptedFloorSeconds ?? steadiness.floor(
            focalLengthMillimetres: profile?.lens.focalLengthMillimetres ?? 50
        )
    }

    /// Swaps the roll — a new stock, or the same stock rated differently. The
    /// medium comes with it, so the tolerance and bias change too.
    public func setLoadedRoll(_ roll: LoadedRoll) {
        guard var updated = profile, updated.body.iso.isFilm else { return }
        updated.body.iso = .fixed(roll)
        store(updated)
    }

    /// The ceiling is the photographer's, not the sensor's, §7d.
    public func setISOCeiling(_ iso: Int) {
        guard var updated = profile, case let .range(minimum, maximum, _) = updated.body.iso else { return }
        updated.body.iso = .range(minimum: minimum, maximum: maximum, ceiling: min(max(iso, minimum), maximum))
        store(updated)
    }

    /// Applies a lever from the no-solution screen and re-solves. The screen is
    /// only worth showing if its buttons do something.
    public func apply(_ lever: ExposureLever) {
        switch lever {
        case let .rate(roll, _):
            setLoadedRoll(roll)
        case let .lowerFloor(shutter, _):
            acceptedFloorSeconds = shutter
        case let .differentRoll(isoSpeed, _):
            // A different *roll*, not the same stock rated harder: past two
            // stops the push is not the answer, so this loads the catalogue
            // stock of the same medium nearest the speed that would work, at
            // its own box speed.
            guard let roll = loadedRoll,
                  let stock = FilmStock.catalogue
                      .filter({ $0.medium == roll.medium && $0.id != roll.stock.id })
                      .min(by: { abs($0.boxSpeed - isoSpeed) < abs($1.boxSpeed - isoSpeed) })
            else { return }
            setLoadedRoll(LoadedRoll(stock: stock))
        case let .raiseCeiling(iso):
            setISOCeiling(iso)
        case .neutralDensity:
            // Nothing to re-solve: the filter is on the lens or it is not.
            break
        }
    }

    private func store(_ updated: GearProfile) {
        // A specific aperture ring chosen on the old lens is not necessarily on
        // the new one's ladder — the aperture-priority solver should not be
        // handed a click stop this lens cannot actually be set to.
        if profile?.lens.id != updated.lens.id {
            chosenAperture = nil
        }
        profile = updated
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        }
        try? gearStore?.save(updated)
        recompute()
    }

    /// The selected gear, in the shape the solver and the barrel drawing want.
    public var lensProfile: LensProfile? { profile.map { LensProfile($0.lens) } }
    public var cameraBodyProfile: CameraBodyProfile? { profile.map { CameraBodyProfile($0.body) } }

    /// The weather the answer on screen was actually built from — the forecast
    /// row when the scrubber has moved, the current observation otherwise.
    ///
    /// Honesty rule 3 is about *this* reading, not about whatever the provider
    /// last returned for now.
    public var activeWeatherReading: WeatherReading? {
        readingForCurrentHour() ?? weather
    }

    /// The segment the control is drawn on: what the user chose, or the segment
    /// nearest whatever the forecast says, so the override opens where the
    /// screen already is rather than jumping to `Clear`.
    public var displayedSky: SkySegment {
        sky ?? SkySegment.nearest(cover: activeWeatherReading?.cloudCover ?? 0)
    }

    /// Whether the cover behind the answer is stale — a forecast past its life,
    /// or a reported sky carried into an hour ahead of now.
    public var isStaleWeather: Bool {
        weatherInput(at: date).freshness == .stale
    }

    /// The cover and freshness the answer is built from, once the manual sky has
    /// had its say.
    ///
    /// A reported sky is an observation of *now*: fresh for the hour the user is
    /// standing in, stale for the hours the scrubber looks ahead to, which is
    /// the §9 widening rather than a claim about a forecast nobody has.
    private func weatherInput(at date: Date) -> (cover: Double?, freshness: WeatherFreshness, precipitation: Precipitation) {
        let reading = readingForCurrentHour() ?? weather
        guard let sky else {
            return (
                reading?.cloudCover,
                reading?.freshness ?? .unavailable,
                reading?.precipitation ?? .none
            )
        }
        let isNow = date <= clock()
        return (sky.cloudCover, isNow ? .fresh : .stale, reading?.precipitation ?? .none)
    }

    /// The calibration in force for the current scene, in stops.
    public var activeCalibrationEV: Double {
        calibrations[currentCalibrationKey] ?? 0
    }

    var currentCalibrationKey: CalibrationKey {
        calibrationKey(at: date)
    }

    /// The regime is decided by the sun at *that* instant, not by the answer
    /// currently on screen: scrubbing across dusk must pick up the night offset
    /// rather than carrying the daylight one over the boundary.
    private func calibrationKey(at date: Date) -> CalibrationKey {
        let elevation = Solar.elevationDegrees(
            date: date,
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude
        )
        return CalibrationKey(
            sceneIdentifier: scene.rawValue,
            isArtificialLight: NightPreset.regime(sunElevationDegrees: elevation) == .night
        )
    }

    private func calibrationEV(at date: Date) -> Double {
        calibrations[calibrationKey(at: date)] ?? 0
    }

    // MARK: Lifecycle

    /// Loads gear, starts location, computes an answer from whatever is already
    /// known, then goes for weather. The screen has numbers on it before the
    /// network is asked for anything.
    public func start() async {
        location.onCoordinateChange = { [weak self] _ in
            guard let self else { return }
            self.recompute()
            Task { await self.refreshWeather() }
        }
        location.start()
        loadGear()
        loadCalibrations()
        recompute()
        await refreshWeather()
    }

    /// Pull-to-refresh: re-asks the provider, then recomputes.
    public func refresh() async {
        await refreshWeather(force: true)
    }

    private func refreshWeather(force: Bool = false) async {
        // Startup, pull-to-refresh and a new fix can all be in flight at once.
        // Only the newest one is allowed to write, or a slow earlier answer
        // lands last and the screen shows the wrong place's sky.
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false } }

        let coordinate = location.coordinate
        let start = Self.hourStart(of: clock())
        let end = start.addingTimeInterval(Double(Self.scrubberHours - 1) * 3_600)

        let current = force
            ? await weatherService.refreshedReading(at: coordinate)
            : await weatherService.reading(at: coordinate)
        let hourly = await weatherService.hourlyReadings(at: coordinate, from: start, through: end)

        guard generation == refreshGeneration else { return }
        weather = current
        hourlyReadings = hourly
        recompute()
    }

    // MARK: Gear

    private func loadGear() {
        guard let gearStore else {
            profiles = GearCatalogue.profiles
            bodies = GearCatalogue.bodies
            lenses = GearCatalogue.lenses
            profile = profiles.first
            return
        }
        do {
            try gearStore.seedIfEmpty()
            profiles = try gearStore.profiles()
            bodies = try gearStore.bodies()
            lenses = try gearStore.lenses()
            profile = try gearStore.selectedProfile() ?? profiles.first
        } catch {
            // A broken store must not cost the photographer the screen: fall
            // back to the shipped catalogue, in memory, for this session.
            profiles = GearCatalogue.profiles
            bodies = GearCatalogue.bodies
            lenses = GearCatalogue.lenses
            profile = profiles.first
        }
    }

    /// Takes a spot from the Map tab: its coordinate, the street it runs along
    /// and the sky it can see, which is exactly the set of inputs the user would
    /// otherwise have to describe (`docs/SPEC-map.md`, "Spot detail").
    public func apply(_ handoff: SpotHandoff) {
        spotName = handoff.name
        streetBearingDegrees = handoff.streetBearingDegrees
        scene = handoff.scene
        location.override = handoff.coordinate
        recompute()
        Task { await refreshWeather(force: true) }
    }

    /// Back to wherever the phone is.
    public func clearSpot() {
        spotName = nil
        streetBearingDegrees = nil
        scene = .openSky
        location.override = nil
        recompute()
    }

    public func select(_ profile: GearProfile) {
        // Same reasoning as `store(_:)`: a different profile can carry a
        // different lens, and a chosen aperture that lens does not have must
        // not survive the switch.
        if self.profile?.lens.id != profile.lens.id {
            chosenAperture = nil
        }
        self.profile = profile
        try? gearStore?.select(profile)
        recompute()
    }

    /// Puts the lens on a different body. The lens, the strategy and the scene
    /// all stay put — the point of the picker is to compare bodies.
    public func setBody(_ body: CameraBody) {
        guard var updated = profile, updated.body.id != body.id else { return }
        updated.body = body
        // A body that cannot be put in A cannot stay in A.
        if !updated.strategy.isAvailable(on: body) {
            updated.strategy = .zoneFocus
        }
        store(updated)
    }

    /// Puts a different lens on the same body. The mirror of `setBody`: the
    /// body, the strategy and the scene all stay put. Unlike a body swap, no
    /// strategy can become unavailable — aperture priority is a property of
    /// the body, not the lens.
    public func setLens(_ lens: Lens) {
        guard var updated = profile, updated.lens.id != lens.id else { return }
        updated.lens = lens
        store(updated)
    }

    public func setStrategy(_ strategy: StoredExposureStrategy) {
        guard var updated = profile, strategy.isAvailable(on: updated.body) else { return }
        updated.strategy = strategy
        profile = updated
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        }
        try? gearStore?.save(updated)
        recompute()
    }

    // MARK: Calibration

    private func loadCalibrations() {
        guard let gearStore, let stored = try? gearStore.calibrationOffsets() else { return }
        calibrations = Dictionary(
            stored.map {
                (
                    CalibrationKey(
                        sceneIdentifier: $0.sceneIdentifier,
                        isArtificialLight: $0.isArtificialLight
                    ),
                    $0.offsetEV
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Stores `measured − modelled` as the offset for this scene, §4d.
    ///
    /// Returns `false` when the delta is too large to be a calibration — a
    /// reading taken through a lens cap would otherwise poison every estimate.
    @discardableResult
    public func storeCalibration(measuredEV100: Double) -> Bool {
        guard let advice else { return false }
        let key = currentCalibrationKey
        let offset = CalibrationOffset(
            sceneIdentifier: key.sceneIdentifier,
            isArtificialLight: key.isArtificialLight,
            offsetEV: measuredEV100 - (advice.estimate.ev100 - activeCalibrationEV),
            measuredAt: clock()
        )
        guard offset.isPlausible else { return false }
        calibrations[key] = offset.offsetEV
        if let gearStore {
            _ = try? gearStore.storeCalibration(offset)
        }
        recompute()
        return true
    }

    public func clearCalibration() {
        let key = currentCalibrationKey
        calibrations[key] = nil
        try? gearStore?.clearCalibration(
            sceneIdentifier: key.sceneIdentifier,
            isArtificialLight: key.isArtificialLight
        )
        recompute()
    }

    // MARK: Alternatives

    /// Promotes a tapped card to the top of the screen.
    public func promote(_ recommendation: ExposureRecommendation) {
        promoted = recommendation
    }

    // MARK: The model

    /// Re-runs the whole chain. Cheap — microseconds — so it runs on every
    /// input change rather than being scheduled.
    public func recompute() {
        guard let profile else {
            advice = nil
            hourlyAdvice = []
            return
        }

        let input = weatherInput(at: date)
        var request = AdviceRequest(
            date: date,
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude,
            cloudCover: input.cover,
            weatherFreshness: input.freshness,
            precipitation: input.precipitation,
            scene: scene,
            subjectLighting: subjectLighting,
            nightPreset: nightPreset,
            calibrationOffsetEV: calibrationEV(at: date) + profile.calibrationOffsetEV,
            body: CameraBodyProfile(profile.body),
            lens: LensProfile(profile.lens),
            strategy: .init(profile.strategy, motion: motion),
            steadiness: steadiness,
            handheldFloorSeconds: acceptedFloorSeconds,
            subjectDistanceMetres: chosenMarkMetres,
            chosenAperture: profile.strategy == .aperturePriority ? chosenAperture : nil
        )

        advice = LightAdvisor.advise(request)
        promoted = nil

        let scrubberStart = Self.hourStart(of: clock())
        request.date = scrubberStart
        hourlyAdvice = LightAdvisor.hourly(
            from: scrubberStart,
            hours: Self.scrubberHours,
            request: request,
            calibrationOffsetEVForHour: { [profile] date in
                self.calibrationEV(at: date) + profile.calibrationOffsetEV
            }
        ) { [hourlyReadings, sky, now = clock()] date in
            // The scrubber does not need a forecast to be worth drawing: the
            // sun is computed on device. A reported sky is held constant across
            // the window, and the hours ahead of now carry the wider σ of §9.
            if let sky {
                return (sky.cloudCover, date <= now ? .fresh : .stale, .none)
            }
            guard let reading = hourlyReadings.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }), abs(reading.date.timeIntervalSince(date)) <= 1_800 else {
                return (nil, .unavailable, .none)
            }
            return (reading.cloudCover, reading.freshness, reading.precipitation)
        }

        events = Solar.events(
            dayStartingAt: Self.dayStart(of: date),
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude
        )
    }

    /// The forecast row for the hour being modelled, when the scrubber has moved
    /// off now.
    private func readingForCurrentHour() -> WeatherReading? {
        guard isScrubbing else { return nil }
        let target = date
        return hourlyReadings.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }
    }

    // MARK: Time

    static func hourStart(of date: Date) -> Date {
        let hour: TimeInterval = 3_600
        let seconds = (date.timeIntervalSinceReferenceDate / hour).rounded(.down) * hour
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Start of the local day, which is what `Solar.events` wants.
    static func dayStart(of date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

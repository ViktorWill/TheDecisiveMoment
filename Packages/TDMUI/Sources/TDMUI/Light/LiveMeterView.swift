import SwiftUI
import TDMLight

#if canImport(AVFoundation) && !targetEnvironment(simulator)
import AVFoundation

/// Exists only to be an active output on the capture session — see
/// `LightMeter`'s note on why one is needed. AVFoundation's delegate callback
/// runs on whatever queue it is registered against, never the main actor, so
/// this is a plain, unisolated `NSObject`, not a `LightMeter` member: nothing
/// here ever needs to touch `LightMeter`'s state.
private final class DiscardingFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Deliberately empty. The buffer is neither read nor retained; it is
        // released the moment this method returns.
    }
}
#endif

/// Reads the camera's own exposure to sanity-check the model, `docs/SPEC-light.md`.
///
/// **Nothing is captured.** A first field test showed why a session with no
/// output at all does not work: `AVCaptureDevice`'s auto-exposure only
/// converges to the live scene while something is actively pulling frames
/// through the pipeline, and with zero outputs there is no such consumer —
/// `iso`/`exposureDuration` stayed near whatever the camera read the instant
/// it opened, regardless of what it was later pointed at. `DiscardingFrameSink`
/// below is that consumer: a buffer is handed to it, and it is not read, not
/// inspected, not stored, and not forwarded anywhere — its callback body is
/// empty. `iso`, `exposureDuration` and `lensAperture` are numbers, not
/// pixels, and remain the only things this class ever actually looks at,
/// which is what makes the Info.plist usage string true.
@MainActor
@Observable
final class LightMeter {
    #if canImport(AVFoundation) && !targetEnvironment(simulator)
    /// Carries `session` into `Task.detached` below.
    ///
    /// `AVCaptureSession.startRunning()`/`stopRunning()` are documented as
    /// safe to call off the main thread — that is the whole reason they are
    /// pushed onto `Task.detached`, since they can block for a noticeable
    /// time. But `AVCaptureSession` predates `Sendable`, and a plain
    /// `nonisolated(unsafe)` on the stored property is not enough on its own:
    /// Swift 6's closure-capture check still flags it as reachable from
    /// main-actor-isolated code, because the property itself remains
    /// `self.session`. Boxing the one value this closure needs, in a type the
    /// compiler unconditionally trusts as `Sendable`, is what actually
    /// satisfies `Task.detached`'s `@Sendable` closure requirement.
    private struct SessionBox: @unchecked Sendable {
        let session: AVCaptureSession
    }
    #endif
    private(set) var measuredEV100: Double?
    private(set) var isRunning = false
    private(set) var isUnavailable = false

    #if canImport(AVFoundation) && !targetEnvironment(simulator)
    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var sampling: Task<Void, Never>?
    @ObservationIgnored private let frameSink = DiscardingFrameSink()
    @ObservationIgnored private let frameSinkQueue = DispatchQueue(label: "com.viktorwill.thedecisivemoment.livemeter.discard")
    #endif

    func start() {
        #if canImport(AVFoundation) && !targetEnvironment(simulator)
        guard !isRunning else { return }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            isUnavailable = true
            return
        }
        self.device = device
        session.beginConfiguration()
        session.sessionPreset = .low
        session.addInput(input)
        // An output whose only job is to exist: see the class-level note on
        // why auto-exposure needs one, and DiscardingFrameSink for what it
        // does with what it is handed, which is nothing.
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(frameSink, queue: frameSinkQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        isRunning = true
        let box = SessionBox(session: session)
        Task.detached { box.session.startRunning() }
        sampling = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        #else
        isUnavailable = true
        #endif
    }

    func stop() {
        #if canImport(AVFoundation) && !targetEnvironment(simulator)
        sampling?.cancel()
        sampling = nil
        isRunning = false
        let box = SessionBox(session: session)
        Task.detached { box.session.stopRunning() }
        #endif
    }

    #if canImport(AVFoundation) && !targetEnvironment(simulator)
    private func sample() {
        guard let device else { return }
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration > 0, device.iso > 0, device.lensAperture > 0 else { return }
        measuredEV100 = ExposureSolver.measuredEV100(
            aperture: Double(device.lensAperture),
            shutter: duration,
            iso: Int(device.iso.rounded())
        )
    }
    #endif
}

/// Model against measurement, and the offer to believe the measurement.
struct LiveMeterView: View {
    let modelledEV100: Double
    let sigmaEV: Double
    let storedOffsetEV: Double
    /// Whether this is the only meter in the bag. On an M-A there is nothing in
    /// the camera to check the model against, so the phone stops being a
    /// cross-check and becomes the meter, `docs/EXPOSURE-MODEL.md` §8.
    var isOnlyMeter: Bool = false
    let onStore: (Double) -> Bool
    let onClear: () -> Void

    @State private var meter = LightMeter()
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isOnlyMeter {
                Text("This body has no meter. This is the reading.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LightTheme.accent)
            }

            Text("No photo is taken. The camera is opened only to read its meter.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(LightTheme.secondaryText)

            if meter.isUnavailable {
                Text("No camera available on this device.")
                    .font(LightTheme.zoneFont)
                    .foregroundStyle(LightTheme.secondaryText)
            } else if let measured = meter.measuredEV100 {
                HStack(spacing: 20) {
                    reading("Model", ExposurePhrasing.exposureValue(modelledEV100, sigmaEV: sigmaEV))
                    reading(isOnlyMeter ? "Metered" : "Measured", "EV " + String(format: "%.1f", measured))
                }

                Text("Difference \(ExposurePhrasing.signedStops(measured - modelledEV100))")
                    .font(LightTheme.zoneFont)
                    .foregroundStyle(agrees(measured) ? LightTheme.secondaryText : LightTheme.caution)

                HStack(spacing: 12) {
                    Button("Use as calibration") {
                        rejected = !onStore(measured)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LightTheme.accent)

                    if storedOffsetEV != 0 {
                        Button("Clear \(ExposurePhrasing.signedStops(storedOffsetEV))", action: onClear)
                            .buttonStyle(.bordered)
                    }
                }

                if rejected {
                    Text("That difference is too large to be a calibration — check the lens is uncovered and the scene is the one you picked.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(LightTheme.caution)
                }
            } else {
                Text(meter.isRunning ? "Metering…" : "Point the phone at the scene.")
                    .font(LightTheme.zoneFont)
                    .foregroundStyle(LightTheme.secondaryText)
            }
        }
        .panel(isOnlyMeter ? "Meter" : "Live meter")
        .task {
            meter.start()
        }
        .onDisappear { meter.stop() }
    }

    /// Inside σ the two agree as well as they can; saying otherwise would claim
    /// precision the model has not got.
    private func agrees(_ measured: Double) -> Bool {
        abs(measured - modelledEV100) <= sigmaEV
    }

    private func reading(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(LightTheme.labelFont)
                .foregroundStyle(LightTheme.secondaryText)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(LightTheme.primaryText)
        }
    }
}

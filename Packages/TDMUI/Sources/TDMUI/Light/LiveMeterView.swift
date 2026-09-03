import SwiftUI
import TDMLight

#if canImport(AVFoundation) && !targetEnvironment(simulator)
import AVFoundation
#endif

/// Reads the camera's own exposure to sanity-check the model, `docs/SPEC-light.md`.
///
/// **Nothing is captured.** The session carries no photo, movie or video-data
/// output: it is started only so that the device applies auto-exposure and
/// publishes `iso`, `exposureDuration` and `lensAperture`, which are numbers, not
/// pixels. No buffer is delivered to the app, so none can be retained — which is
/// what makes the Info.plist usage string true.
@MainActor
@Observable
final class LightMeter {
    private(set) var measuredEV100: Double?
    private(set) var isRunning = false
    private(set) var isUnavailable = false

    #if canImport(AVFoundation) && !targetEnvironment(simulator)
    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var sampling: Task<Void, Never>?
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
        // Deliberately no output of any kind: see the note above.
        session.commitConfiguration()

        isRunning = true
        let session = session
        Task.detached { session.startRunning() }
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
        let session = session
        Task.detached { session.stopRunning() }
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

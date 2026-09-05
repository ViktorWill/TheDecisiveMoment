import SwiftUI
import TDMCore
import TDMLight

/// Manual mode: the photographer picks aperture, shutter and ISO directly,
/// and the screen reports what that combination does — the same zone-focus
/// scale and freeze-motion floor automatic mode uses, plus a same-formula
/// read on whether the exposure itself is close. It never refuses a
/// combination; `docs/SPEC-light.md`'s automatic mode is where the app
/// argues with the photographer, not this one.
struct ManualExposureView: View {
    @Bindable var viewModel: LightViewModel
    let lens: Lens
    let cameraBody: CameraBody

    private var markMetres: Double {
        viewModel.chosenMarkMetres ?? lens.sortedDistanceMarks.last ?? .infinity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelled("Aperture") {
                ChipPicker(
                    values: lens.sortedApertures,
                    title: ExposurePhrasing.aperture,
                    selection: Binding(
                        get: { viewModel.manualAperture ?? lens.sortedApertures.first ?? 0 },
                        set: { viewModel.manualAperture = $0 }
                    )
                )
            }

            labelled("Shutter") {
                ChipPicker(
                    values: cameraBody.sortedShutterSpeeds,
                    title: { ExposurePhrasing.shutter($0) },
                    selection: Binding(
                        get: { viewModel.manualShutter ?? cameraBody.sortedShutterSpeeds.first ?? 0 },
                        set: { viewModel.manualShutter = $0 }
                    )
                )
            }

            if cameraBody.iso.availableValues.count > 1 {
                labelled("ISO") {
                    ChipPicker(
                        values: cameraBody.iso.availableValues,
                        title: BodyPhrasing.number,
                        selection: Binding(
                            get: { viewModel.manualISO ?? cameraBody.iso.availableValues.first ?? 0 },
                            set: { viewModel.manualISO = $0 }
                        )
                    )
                }
            }

            labelled("Subject") {
                ChipPicker(
                    values: SubjectMotion.allCases,
                    title: { InputControlsView.name(of: $0) },
                    selection: $viewModel.motion
                )
            }

            status
        }
        .onAppear(perform: primeDefaults)
        .panel("Manual")

        if let lensProfile = viewModel.lensProfile, let bodyProfile = viewModel.cameraBodyProfile,
           let aperture = viewModel.manualAperture {
            ZoneScaleView(
                lens: lensProfile,
                cameraBody: bodyProfile,
                aperture: aperture,
                markMetres: Binding(
                    get: { markMetres },
                    set: { viewModel.chosenMarkMetres = $0 }
                ),
                recommendedMarkMetres: nil
            )
            .panel("Zone focus")
        }
    }

    /// A picker with nothing chosen yet can't show a meaningful state.
    /// Aperture and shutter land in the middle of their ladders — a moderate
    /// starting point, not an edge; ISO starts at the body's lowest, the
    /// ordinary rule of raising it only when the light actually needs it.
    private func primeDefaults() {
        if viewModel.manualAperture == nil {
            viewModel.manualAperture = lens.sortedApertures[lens.sortedApertures.count / 2]
        }
        if viewModel.manualShutter == nil {
            viewModel.manualShutter = cameraBody.sortedShutterSpeeds[cameraBody.sortedShutterSpeeds.count / 2]
        }
        if viewModel.manualISO == nil {
            viewModel.manualISO = cameraBody.iso.availableValues.first
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let freezes = viewModel.manualFreezesMotion {
                let subject = InputControlsView.name(of: viewModel.motion)
                statusRow(
                    systemImage: freezes ? "checkmark.circle" : "exclamationmark.triangle",
                    text: freezes ? "\(subject) will be frozen." : "\(subject) may blur at this shutter.",
                    tint: freezes ? LightTheme.accent : LightTheme.curated
                )
            }
            if let warning = viewModel.manualExposureWarning {
                statusRow(systemImage: "exclamationmark.triangle", text: warning, tint: LightTheme.curated)
            }
        }
    }

    private func statusRow(systemImage: String, text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(LightTheme.labelFont)
                .foregroundStyle(LightTheme.secondaryText)
            content()
        }
    }
}

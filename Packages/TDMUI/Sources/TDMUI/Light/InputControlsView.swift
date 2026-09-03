import SwiftUI
import TDMCore
import TDMLight

/// The inputs, two taps each: pick the row, pick the value.
///
/// Nothing here is a free-text field or a slider with a hundred positions —
/// standing in a street at night, the interaction budget is two taps and the
/// answer has to change immediately.
struct InputControlsView: View {
    @Bindable var viewModel: LightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelled("Scene") {
                ChipPicker(values: ScenePreset.allCases, title: Self.name(of:), selection: $viewModel.scene)
            }

            labelled("Subject light") {
                ChipPicker(values: SubjectLighting.allCases, title: Self.name(of:), selection: $viewModel.subjectLighting)
            }

            if viewModel.advice?.estimate.regime == .night {
                labelled("Street") {
                    ChipPicker(values: NightPreset.allCases, title: Self.name(of:), selection: $viewModel.nightPreset)
                }
            }

            labelled("Strategy") {
                ChipPicker(values: StoredExposureStrategy.allCases, title: Self.name(of:), selection: Binding(
                        get: { viewModel.profile?.strategy ?? .zoneFocus },
                        set: { viewModel.setStrategy($0) }
                    ))
            }

            if viewModel.profile?.strategy == .freezeMotion {
                labelled("Motion") {
                    ChipPicker(values: SubjectMotion.allCases, title: Self.name(of:), selection: $viewModel.motion)
                }
            }

            labelled("Hold") {
                ChipPicker(values: HandheldSteadiness.allCases, title: Self.name(of:), selection: $viewModel.steadiness)
            }
        }
        .panel("Conditions")
    }

    /// A caption above a row of chips. The caption is the first tap's target in
    /// the sense that matters: it tells you which row you are about to change.
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    // MARK: Names
    //
    // Spelt out here rather than on the model types: `TDMLight` is a maths
    // package and has no business carrying display strings.

    static func name(of scene: ScenePreset) -> String {
        switch scene {
        case .openSky: "Open sky"
        case .shadedSideOfStreet: "Shaded side"
        case .narrowCanyon: "Canyon"
        case .underArcade: "Arcade"
        case .interior: "Interior"
        }
    }

    static func name(of lighting: SubjectLighting) -> String {
        switch lighting {
        case .frontLit: "Front-lit"
        case .sideLit: "Side-lit"
        case .backLit: "Back-lit"
        case .horizontalPlane: "Ground"
        }
    }

    static func name(of preset: NightPreset) -> String {
        switch preset {
        case .brightNeon: "Neon"
        case .litCommercialStreet: "Lit street"
        case .residentialStreet: "Residential"
        case .dimSideStreet: "Dim"
        }
    }

    static func name(of strategy: StoredExposureStrategy) -> String {
        switch strategy {
        case .zoneFocus: "Zone focus"
        case .freezeMotion: "Freeze motion"
        case .subjectIsolation: "Isolate"
        case .availableLight: "Available light"
        }
    }

    static func name(of motion: SubjectMotion) -> String {
        switch motion {
        case .walking: "Walking"
        case .running: "Running"
        }
    }

    static func name(of steadiness: HandheldSteadiness) -> String {
        switch steadiness {
        case .standard: "1/focal"
        case .rangefinder: "1/2·focal"
        }
    }
}

/// Which body and lens the advice is for.
struct GearPickerView: View {
    let profiles: [GearProfile]
    let selected: GearProfile?
    let onSelect: (GearProfile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    Button {
                        onSelect(profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.body.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(profile.lens.name)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(LightTheme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(profile.id == selected?.id ? LightTheme.accent.opacity(0.25) : LightTheme.raised)
                        )
                        .foregroundStyle(LightTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
        .panel("Gear")
    }
}

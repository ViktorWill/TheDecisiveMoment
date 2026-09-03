import SwiftUI
import TDMCore
import TDMLight
import TDMPersistence
import TDMWeather

/// The Light tab, per `docs/SPEC-light.md`.
///
/// Order is the argument: the answer first, then the barrel it is set on, then
/// the alternatives, then everything that explains it. Scrolling down is
/// optional — the top of the screen is the whole feature.
public struct LightView: View {
    @State private var viewModel: LightViewModel
    @State private var showsMeter = false

    public init(
        weatherService: WeatherService,
        gearStore: GearStore? = nil
    ) {
        _viewModel = State(
            wrappedValue: LightViewModel(weatherService: weatherService, gearStore: gearStore)
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let advice = viewModel.advice {
                        AnswerHeaderView(
                            advice: advice,
                            recommendation: viewModel.recommendation,
                            solverError: advice.solverError,
                            cloudCover: viewModel.activeWeatherReading?.cloudCover,
                            isStaleWeather: viewModel.activeWeatherReading?.freshness == .stale,
                            isScrubbing: viewModel.isScrubbing,
                            scrubbedTo: viewModel.date
                        )

                        if let lens = viewModel.lensProfile,
                           let cameraBody = viewModel.cameraBodyProfile,
                           let mark = viewModel.selectedMarkMetres,
                           let aperture = viewModel.recommendation?.aperture {
                            ZoneScaleView(
                                lens: lens,
                                cameraBody: cameraBody,
                                aperture: aperture,
                                markMetres: Binding(
                                    get: { mark },
                                    set: { viewModel.chosenMarkMetres = $0 }
                                ),
                                recommendedMarkMetres: advice.focusMarkMetres
                            )
                            .panel("Zone focus")
                        }

                        if !viewModel.alternatives.isEmpty {
                            AlternativesRowView(
                                alternatives: viewModel.alternatives,
                                onPromote: viewModel.promote
                            )
                            .panel("Alternatives")
                        }

                        SunPanelView(
                            sun: advice.sun,
                            events: viewModel.events,
                            now: viewModel.date,
                            streetBearingDegrees: viewModel.streetBearingDegrees
                        )

                        if !viewModel.hourlyAdvice.isEmpty {
                            TimeScrubberView(
                                hourly: viewModel.hourlyAdvice,
                                events: viewModel.events,
                                hourOffset: Binding(
                                    get: { viewModel.hourOffset },
                                    set: { viewModel.hourOffset = $0 }
                                )
                            )
                        }

                        InputControlsView(viewModel: viewModel)

                        GearPickerView(
                            profiles: viewModel.profiles,
                            selected: viewModel.profile,
                            onSelect: viewModel.select
                        )

                        if showsMeter {
                            LiveMeterView(
                                modelledEV100: advice.estimate.ev100,
                                sigmaEV: advice.estimate.sigmaEV,
                                storedOffsetEV: viewModel.activeCalibrationEV,
                                onStore: { viewModel.storeCalibration(measuredEV100: $0) },
                                onClear: viewModel.clearCalibration
                            )
                        }

                        if viewModel.location.isUsingFallback {
                            Text("Using a default location — the sun figures are for Times Square until there is a fix.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(LightTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ProgressView()
                            .padding(.top, 60)
                    }
                }
                .padding(16)
            }
            .background(LightTheme.background)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Light")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsMeter.toggle()
                    } label: {
                        Label("Live meter", systemImage: showsMeter ? "gauge.with.dots.needle.bottom.50percent" : "gauge")
                    }
                    .accessibilityLabel(showsMeter ? "Hide the live meter" : "Show the live meter")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
    }
}

#Preview {
    LightView(
        weatherService: WeatherService(provider: StubWeatherProvider()),
        gearStore: nil
    )
}

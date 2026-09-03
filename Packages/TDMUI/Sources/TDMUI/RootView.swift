import SwiftUI
import TDMPersistence
import TDMWeather

/// The tab shell. Three sections, as described in `docs/ARCHITECTURE.md`.
public struct RootView: View {
    private let weatherService: WeatherService
    private let gearStore: GearStore?

    /// - Parameters:
    ///   - weatherService: Live in the app, a stub in previews and tests.
    ///   - gearStore: `nil` falls back to the shipped catalogue in memory, which
    ///     is what previews want and what a broken store gets.
    public init(weatherService: WeatherService, gearStore: GearStore? = nil) {
        self.weatherService = weatherService
        self.gearStore = gearStore
    }

    public var body: some View {
        TabView {
            MapPlaceholderView()
                .tabItem { Label("Map", systemImage: "map") }

            LightView(weatherService: weatherService, gearStore: gearStore)
                .tabItem { Label("Light", systemImage: "sun.max") }

            CommunityPlaceholderView()
                .tabItem { Label("Community", systemImage: "person.2") }
        }
        // The app is used at dusk and at night; a white screen ruins night
        // vision and exposure judgement.
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView(weatherService: WeatherService(provider: StubWeatherProvider()))
}

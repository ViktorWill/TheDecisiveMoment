import SwiftUI
import TDMPersistence
import TDMSpots
import TDMWeather

/// The tab shell. Three sections, as described in `docs/ARCHITECTURE.md`.
public struct RootView: View {
    private let weatherService: WeatherService
    private let gearStore: GearStore?
    private let spotStore: any SpotStore
    private let bundles: BundleService?

    /// One provider for both tabs: two `CLLocationManager`s would ask for the
    /// same fix twice and cost the battery for it.
    @State private var location = LocationProvider()
    @State private var selectedTab = Tab.map
    /// The spot the Map handed to the Light tab, if any.
    @State private var handoff: SpotHandoff?

    enum Tab: Hashable {
        case map
        case light
        case community
    }

    /// - Parameters:
    ///   - weatherService: Live in the app, a stub in previews and tests.
    ///   - gearStore: `nil` falls back to the shipped catalogue in memory, which
    ///     is what previews want and what a broken store gets.
    ///   - spotStore: Where bundles and pins live. An in-memory store keeps
    ///     previews working without SwiftData.
    ///   - bundles: `nil` leaves the map offline-only — it still draws whatever
    ///     is stored.
    public init(
        weatherService: WeatherService,
        gearStore: GearStore? = nil,
        spotStore: any SpotStore = InMemorySpotStore(),
        bundles: BundleService? = nil
    ) {
        self.weatherService = weatherService
        self.gearStore = gearStore
        self.spotStore = spotStore
        self.bundles = bundles
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            MapView(
                store: spotStore,
                bundles: bundles,
                gearStore: gearStore,
                weather: weatherService,
                location: location
            ) { spot in
                handoff = spot
                selectedTab = .light
            }
            .tabItem { Label("Map", systemImage: "map") }
            .tag(Tab.map)

            LightView(weatherService: weatherService, gearStore: gearStore, handoff: handoff)
                .tabItem { Label("Light", systemImage: "sun.max") }
                .tag(Tab.light)

            CommunityPlaceholderView()
                .tabItem { Label("Community", systemImage: "person.2") }
                .tag(Tab.community)
        }
        // The app is used at dusk and at night; a white screen ruins night
        // vision and exposure judgement.
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView(weatherService: WeatherService(provider: StubWeatherProvider()))
}

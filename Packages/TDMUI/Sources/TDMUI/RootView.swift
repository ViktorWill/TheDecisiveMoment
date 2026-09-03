import SwiftUI
import TDMCore
import TDMPersistence
import TDMSpots
import TDMWeather

/// The tab shell. Three sections, as described in `docs/ARCHITECTURE.md`.
public struct RootView: View {
    private let weatherService: WeatherService
    private let gearStore: GearStore?
    private let spotStore: any SpotStore
    private let bundles: BundleService?
    private let community: any CommunityBackend

    /// One provider for both tabs: two `CLLocationManager`s would ask for the
    /// same fix twice and cost the battery for it.
    @State private var location = LocationProvider()
    @State private var selectedTab = Tab.map
    /// The spot the Map handed to the Light tab, if any.
    @State private var handoff: SpotHandoff?
    /// Shown once, before anything asks for a permission.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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
    ///   - community: Where shooting plans live. The in-memory default keeps
    ///     previews working, and is what a store that will not open falls back
    ///     to: losing a plan on quit beats refusing to draw the tab.
    public init(
        weatherService: WeatherService,
        gearStore: GearStore? = nil,
        spotStore: any SpotStore = InMemorySpotStore(),
        bundles: BundleService? = nil,
        community: any CommunityBackend = InMemoryCommunityBackend()
    ) {
        self.weatherService = weatherService
        self.gearStore = gearStore
        self.spotStore = spotStore
        self.bundles = bundles
        self.community = community
    }

    public var body: some View {
        // Not a cover over the tabs: a tab underneath would run its `task` and
        // put a location prompt on screen behind the explanation of what the
        // app is.
        if hasSeenOnboarding {
            tabs
        } else {
            OnboardingView { hasSeenOnboarding = true }
                .preferredColorScheme(.dark)
        }
    }

    private var tabs: some View {
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

            CommunityView(
                model: CommunityViewModel(
                    backend: community,
                    store: spotStore,
                    location: location
                )
            )
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

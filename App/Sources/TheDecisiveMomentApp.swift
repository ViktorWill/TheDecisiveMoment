import SwiftUI
import TDMCore
import TDMPersistence
import TDMSpots
import TDMUI
import TDMWeather

@main
@MainActor
struct TheDecisiveMomentApp: App {
    /// One cache for the whole app. Fifteen minutes, and a clear-sky fallback
    /// when the network is not there — the screen never blocks on it.
    @State private var weatherService = WeatherService(provider: WeatherKitProvider())
    /// A store that will not open must not cost the user the screen: the view
    /// model falls back to the shipped catalogue in memory when this is `nil`.
    @State private var gearStore: GearStore? = Self.makeGearStore()
    /// Bundles and pins, and the download flow over them. A store that will not
    /// open falls back to memory, which costs the user this session's pins
    /// rather than the whole map.
    @State private var spots: SpotServices = Self.makeSpotServices()
    /// Shooting plans. A store that will not open falls back to memory: losing
    /// a plan on quit is bad, refusing to draw the tab is worse.
    private let community: any CommunityBackend = Self.makeCommunityBackend()

    private static func makeGearStore() -> GearStore? {
        guard let container = try? GearStore.makeContainer() else { return nil }
        return GearStore(container: container)
    }

    /// The store and the service built over it, made together so there is
    /// exactly one store behind both.
    struct SpotServices {
        let store: any SpotStore
        let bundles: BundleService

        init(store: any SpotStore) {
            self.store = store
            self.bundles = BundleService(store: store)
        }
    }

    private static func makeSpotServices() -> SpotServices {
        guard let container = try? SwiftDataSpotStore.makeContainer() else {
            return SpotServices(store: InMemorySpotStore())
        }
        return SpotServices(store: SwiftDataSpotStore.make(container: container))
    }

    private static func makeCommunityBackend() -> any CommunityBackend {
        guard let container = try? LocalCommunityBackend.makeContainer() else {
            return InMemoryCommunityBackend()
        }
        return LocalCommunityBackend.make(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                weatherService: weatherService,
                gearStore: gearStore,
                spotStore: spots.store,
                bundles: spots.bundles,
                community: community
            )
        }
    }
}

import SwiftUI
import TDMPersistence
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

    private static func makeGearStore() -> GearStore? {
        guard let container = try? GearStore.makeContainer() else { return nil }
        return GearStore(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView(weatherService: weatherService, gearStore: gearStore)
        }
    }
}

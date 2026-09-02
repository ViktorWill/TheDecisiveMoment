import SwiftUI

/// The tab shell. Three sections, as described in `docs/ARCHITECTURE.md`.
public struct RootView: View {
    public init() {}

    public var body: some View {
        TabView {
            MapPlaceholderView()
                .tabItem { Label("Map", systemImage: "map") }

            LightPlaceholderView()
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
    RootView()
}

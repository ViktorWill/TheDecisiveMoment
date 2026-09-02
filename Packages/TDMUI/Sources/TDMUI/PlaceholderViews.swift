import SwiftUI

/// Placeholder for the spot map — see `docs/SPEC-map.md`.
struct MapPlaceholderView: View {
    var body: some View {
        PlaceholderView(title: "Map", detail: "Spots for the city you are standing in.")
    }
}

/// Placeholder for the light advisor — see `docs/SPEC-light.md`.
struct LightPlaceholderView: View {
    var body: some View {
        PlaceholderView(title: "Light", detail: "What to set, and where to put the zone focus.")
    }
}

/// Placeholder for the community section — see `docs/SPEC-community.md`.
struct CommunityPlaceholderView: View {
    var body: some View {
        PlaceholderView(title: "Community", detail: "Photographers shooting the same city.")
    }
}

private struct PlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "camera.viewfinder", description: Text(detail))
                .navigationTitle(title)
        }
    }
}

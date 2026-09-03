import SwiftUI

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

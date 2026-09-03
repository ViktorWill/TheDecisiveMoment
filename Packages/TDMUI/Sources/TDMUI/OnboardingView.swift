import SwiftUI

/// What the three tabs are for, shown once.
///
/// It asks for nothing. Location is requested when the Map or Light tab first
/// needs a fix, and the camera when the live meter is switched on — a screen of
/// permission prompts before the app has done anything useful is a screen of
/// questions the user has no way to answer.
struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The Decisive Moment")
                        .scaledFont(size: 28, weight: .semibold)
                        .foregroundStyle(MapTheme.primaryText)
                    Text("A field companion for street photography. It works without a signal.")
                        .scaledFont(size: 15)
                        .foregroundStyle(MapTheme.secondaryText)
                }

                ForEach(Self.sections, id: \.title) { section in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: section.symbol)
                            .scaledFont(size: 20)
                            .foregroundStyle(MapTheme.accent)
                            .frame(width: 28, alignment: .center)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .scaledFont(size: 17, weight: .semibold)
                                .foregroundStyle(MapTheme.primaryText)
                            Text(section.detail)
                                .scaledFont(size: 14)
                                .foregroundStyle(MapTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(MapTheme.primaryText)
                    Text("Location is asked for when a screen needs to know where the sun is. The camera is asked for only if you switch on the light meter, and no photo is taken or stored. Nothing you write down leaves the device.")
                        .scaledFont(size: 13)
                        .foregroundStyle(MapTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onDone) {
                    Text("Start")
                        .scaledFont(size: 16, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(MapTheme.accent)
                .foregroundStyle(MapTheme.background)
            }
            .padding(MapTheme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MapTheme.background)
    }

    /// Not called `Section`: that name is `SwiftUI.Section`, and shadowing it
    /// inside a view is a trap for the next edit.
    private struct TabExplanation {
        let symbol: String
        let title: String
        let detail: String
    }

    private static let sections = [
        TabExplanation(
            symbol: "map",
            title: "Map",
            detail: "Places worth standing in, downloaded a city at a time and kept on the device. Drop your own pins; they stay yours."
        ),
        TabExplanation(
            symbol: "sun.max",
            title: "Light",
            detail: "What the light is doing now and for the next twelve hours, and the aperture, shutter and zone-focus setting that go with it."
        ),
        TabExplanation(
            symbol: "person.2",
            title: "Community",
            detail: "Your own shooting plans for now, private to this device. Later, other photographers shooting the same city."
        )
    ]
}

#Preview {
    OnboardingView {}
}

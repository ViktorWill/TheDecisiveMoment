import SwiftUI

/// Liquid Glass, where the current design guidance says it belongs: floating
/// controls, never the content underneath them.
///
/// The app's deployment target is iOS 18, so the effect is availability-gated
/// and falls back to a flat raised fill. It is also skipped when the user has
/// asked for reduced transparency, and — since this app is used at night — the
/// fallback is the darker of the two, never the brighter.
struct FloatingControlBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(
                    isSelected ? .regular.tint(LightTheme.accent.opacity(0.35)) : .regular,
                    in: Capsule()
                )
        } else {
            content
                .background(
                    isSelected ? LightTheme.accent.opacity(0.28) : LightTheme.raised,
                    in: Capsule()
                )
        }
    }
}

extension View {
    /// A floating control: a chip, a segment, a button over content.
    func floatingControl(isSelected: Bool = false) -> some View {
        modifier(FloatingControlBackground(isSelected: isSelected))
    }
}

/// A row of chips where exactly one is chosen. Two taps to change anything: one
/// to look, one to set — which is all the spec allows for scene and subject.
struct ChipPicker<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let isSelected = value == selection
                    Button {
                        selection = value
                    } label: {
                        Text(title(value))
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isSelected ? LightTheme.primaryText : LightTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .floatingControl(isSelected: isSelected)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

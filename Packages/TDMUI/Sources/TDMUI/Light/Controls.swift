import SwiftUI

struct FloatingControlBackground: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? LightTheme.accent.opacity(0.28) : LightTheme.raised,
                in: Capsule()
            )
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
        // No shadow or glow on a chip that clipping would cut into — and
        // without that, disabling the scroll view's own clip just lets
        // unscrolled content bleed past the panel() it sits in.
    }
}

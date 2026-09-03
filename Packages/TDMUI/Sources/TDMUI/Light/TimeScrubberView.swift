import SwiftUI
import TDMLight

/// Twelve hours of the model, one sample an hour, with the light drawn rather
/// than tabulated.
///
/// Golden and blue hour are shaded because that is the shape a photographer
/// plans around; EV and sun elevation are sparklines because their *slope* is
/// the useful part, not any single value.
struct TimeScrubberView: View {
    let hourly: [Advice]
    let events: SolarEvents?
    @Binding var hourOffset: Int

    private var evRange: ClosedRange<Double> {
        let values = hourly.map(\.estimate.ev100)
        guard let low = values.min(), let high = values.max(), high > low else { return 0...1 }
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Next 12 hours")
                    .font(LightTheme.labelFont)
                    .foregroundStyle(LightTheme.secondaryText)
                Spacer()
                if let selected = hourly[safe: hourOffset] {
                    Text(
                        ExposurePhrasing.exposureValue(
                            selected.estimate.ev100,
                            sigmaEV: selected.estimate.sigmaEV
                        )
                    )
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(LightTheme.primaryText)
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let step = hourly.count > 1 ? width / CGFloat(hourly.count - 1) : width

                ZStack(alignment: .topLeading) {
                    shading(width: width, height: height)
                    sparkline(height: height, step: step, value: evFraction)
                        .stroke(LightTheme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    sparkline(height: height, step: step, value: elevationFraction)
                        .stroke(LightTheme.golden.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    marker(step: step, height: height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let index = Int((value.location.x / max(step, 1)).rounded())
                        hourOffset = min(max(index, 0), max(hourly.count - 1, 0))
                    }
                )
            }
            .frame(height: 74)

            HStack(spacing: 0) {
                ForEach(Array(hourly.enumerated()), id: \.offset) { index, advice in
                    Text(advice.date, format: .dateTime.hour())
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(index == hourOffset ? LightTheme.accent : LightTheme.secondaryText.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .panel("Ahead")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Twelve hour forecast")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? hourOffset + 1 : hourOffset - 1
            hourOffset = min(max(next, 0), max(hourly.count - 1, 0))
        }
    }

    // MARK: Drawing

    /// Fraction from the bottom of the plot, 0…1.
    private func evFraction(_ advice: Advice) -> CGFloat {
        let range = evRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return CGFloat((advice.estimate.ev100 - range.lowerBound) / span)
    }

    /// −10°…+70° mapped to the plot, so the horizon sits at a fixed height and
    /// the curve is comparable between hours and between days.
    private func elevationFraction(_ advice: Advice) -> CGFloat {
        CGFloat((min(max(advice.sun.elevationDegrees, -10), 70) + 10) / 80)
    }

    private func sparkline(height: CGFloat, step: CGFloat, value: (Advice) -> CGFloat) -> Path {
        Path { path in
            for (index, advice) in hourly.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * step,
                    y: height - value(advice) * (height - 8) - 4
                )
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    /// Golden and blue hour, shaded where they fall in the twelve hours shown.
    private func shading(width: CGFloat, height: CGFloat) -> some View {
        let windows: [(TimeWindow, Color)] = [
            (events?.morningBlueHour, LightTheme.blue),
            (events?.eveningBlueHour, LightTheme.blue),
            (events?.morningGoldenHour, LightTheme.golden),
            (events?.eveningGoldenHour, LightTheme.golden)
        ].compactMap { window, colour in window.map { ($0, colour) } }

        return ZStack(alignment: .topLeading) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, entry in
                if let span = span(of: entry.0, width: width) {
                    Rectangle()
                        .fill(entry.1.opacity(0.22))
                        .frame(width: span.width, height: height)
                        .offset(x: span.start)
                }
            }
        }
    }

    /// Where a window falls on the axis, clipped to the plot. `nil` when it is
    /// entirely outside the twelve hours on screen.
    private func span(of window: TimeWindow, width: CGFloat) -> (start: CGFloat, width: CGFloat)? {
        guard let first = hourly.first?.date, let last = hourly.last?.date, last > first else { return nil }
        let total = last.timeIntervalSince(first)
        let startFraction = window.start.timeIntervalSince(first) / total
        let endFraction = window.end.timeIntervalSince(first) / total
        let clampedStart = min(max(startFraction, 0), 1)
        let clampedEnd = min(max(endFraction, 0), 1)
        guard clampedEnd > clampedStart else { return nil }
        return (CGFloat(clampedStart) * width, CGFloat(clampedEnd - clampedStart) * width)
    }

    private func marker(step: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(LightTheme.primaryText.opacity(0.85))
            .frame(width: 2, height: height)
            .offset(x: CGFloat(hourOffset) * step - 1)
            .animation(.snappy(duration: 0.15), value: hourOffset)
    }

    private var accessibilityValue: String {
        guard let selected = hourly[safe: hourOffset] else { return "No forecast" }
        return ExposurePhrasing.exposureValue(selected.estimate.ev100, sigmaEV: selected.estimate.sigmaEV)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

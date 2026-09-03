import SwiftUI
import TDMCore
import TDMSpots

/// One annotation: a spot, or a bubble standing for several.
///
/// Size and opacity carry the score — which is why the map needs no legend —
/// and the glyph carries the kind. A marker too small to hold a glyph becomes
/// the plain dot of `design/Map.dc.html`, because an illegible glyph is worse
/// than none.
struct SpotMarkerView: View {
    let cluster: SpotCluster

    var body: some View {
        if cluster.isSingle {
            marker(for: cluster.representative)
        } else {
            bubble
        }
    }

    private func marker(for spot: Spot) -> some View {
        let radius = MapTheme.markerRadius(score: spot.score)
        let isLocal = spot.sources.contains(.local)
        return ZStack {
            Circle()
                .fill(MapTheme.markerFill(score: spot.score, curated: spot.curated))
                .opacity(MapTheme.markerOpacity(score: spot.score))
                .overlay(
                    Circle().stroke(
                        isLocal ? MapTheme.accent : MapTheme.ground,
                        style: StrokeStyle(lineWidth: 2, dash: isLocal ? [3, 2] : [])
                    )
                )
            if radius >= MapTheme.glyphThresholdRadius {
                Image(systemName: MapTheme.symbol(for: spot.kind))
                    .font(.system(size: radius * 0.85, weight: .regular))
                    .foregroundStyle(spot.curated ? MapTheme.background : MapTheme.glyph)
            } else {
                Circle()
                    .fill(MapTheme.markerDot)
                    .frame(width: 5.2, height: 5.2)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityLabel(spot.name)
        .accessibilityValue(SpotProse.scoreSummary(for: spot))
    }

    /// The bubble adopts the colour of its highest-scoring member, so a cluster
    /// hiding a curated spot still reads as worth opening.
    private var bubble: some View {
        ZStack {
            Circle()
                .fill(MapTheme.clusterFill)
                .overlay(
                    Circle().stroke(
                        cluster.containsCurated ? MapTheme.curated : MapTheme.clusterStroke,
                        lineWidth: 1.5
                    )
                )
            Text("\(cluster.count)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(MapTheme.secondaryText)
        }
        .frame(width: 38, height: 38)
        .accessibilityLabel("\(cluster.count) spots")
    }
}

import SwiftUI
import TDMCore
import TDMSpots

/// The sheet below the map: search, filter pills, and the ranked list
/// (`docs/SPEC-map.md`, "Layout").
struct MapSheetView: View {
    @Bindable var model: MapViewModel
    @Binding var selectedSpot: Spot?
    let openLight: (SpotHandoff) -> Void
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                handle
                searchRow
                pills
                if let note = model.annotationLimitNote {
                    Text(note)
                        .font(MapTheme.creditFont)
                        .foregroundStyle(MapTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MapTheme.gutter)
                        .padding(.top, 8)
                }
                Divider()
                    .overlay(MapTheme.hairline)
                    .padding(.top, 14)
                list
            }
            .background(MapTheme.sheet)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedSpot) { spot in
                SpotDetailView(
                    spot: spot,
                    origin: model.listOrigin,
                    profile: model.gearProfile,
                    weather: model.weather,
                    openLight: openLight,
                    deletePin: { id in Task { await model.deletePin(id: id) } }
                )
            }
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(MapTheme.handle)
            .frame(width: 36, height: 4)
            .padding(.top, 9)
            .padding(.bottom, 4)
    }

    private var searchRow: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MapTheme.tertiaryText)
                TextField(
                    "",
                    text: $model.searchText,
                    prompt: Text("Search spots and tags")
                        .foregroundStyle(MapTheme.tertiaryText)
                )
                .font(.system(size: 14))
                .foregroundStyle(MapTheme.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MapTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: MapTheme.searchFieldHeight)
            .background(MapTheme.field, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                    .stroke(MapTheme.hairline, lineWidth: 1)
            )

            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15))
                    .foregroundStyle(MapTheme.secondaryText)
                    .frame(width: MapTheme.searchFieldHeight, height: MapTheme.searchFieldHeight)
                    .background(MapTheme.control, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                            .stroke(MapTheme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map settings")
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 8)
    }

    /// Multi-select, persisted between launches. *Lit now* is first because it
    /// is the one that gets used.
    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                pill(
                    "Lit now",
                    systemImage: "sun.max",
                    isOn: model.filters.litNow,
                    tint: MapTheme.accent
                ) {
                    model.filters.litNow.toggle()
                }

                pill(
                    "Curated",
                    isOn: model.filters.sources.contains(.curated),
                    tint: MapTheme.curated
                ) {
                    model.filters.toggle(source: .curated)
                }

                pill(
                    "My pins",
                    isOn: model.filters.sources.contains(.local),
                    tint: MapTheme.accent
                ) {
                    model.filters.toggle(source: .local)
                }

                ForEach(Self.offeredKinds, id: \.self) { kind in
                    pill(
                        SpotProse.label(for: kind).capitalizedFirst,
                        isOn: model.filters.kinds.contains(kind),
                        tint: MapTheme.accent
                    ) {
                        model.filters.toggle(kind: kind)
                    }
                }

                ForEach(Openness.allCases, id: \.self) { openness in
                    pill(
                        SpotProse.label(for: openness).capitalizedFirst,
                        isOn: model.filters.openness.contains(openness),
                        tint: MapTheme.accent
                    ) {
                        model.filters.toggle(openness: openness)
                    }
                }

                scoreFloorPill
            }
            .padding(.horizontal, MapTheme.gutter)
        }
        .padding(.top, 12)
    }

    /// The kinds worth a pill. The rest are reachable by search — a row of
    /// fourteen pills is a row nobody reads.
    static let offeredKinds: [SpotKind] = [.plaza, .market, .street, .stairs, .transit, .park, .bridge, .viewpoint]

    static let scoreFloors: [Double] = [0, 0.2, 0.3, 0.5, 0.7]

    private var scoreFloorPill: some View {
        Menu {
            ForEach(Self.scoreFloors, id: \.self) { floor in
                Button {
                    model.filters.minimumScore = floor
                } label: {
                    Text(floor == 0 ? "Everything" : "\(Self.floorLabel(floor))+")
                }
            }
        } label: {
            pillLabel(
                Self.floorLabel(model.filters.minimumScore) + "+",
                systemImage: nil,
                isOn: model.filters.minimumScore != MapFilters.defaultMinimumScore,
                tint: MapTheme.accent
            )
        }
        .accessibilityLabel("Score floor")
    }

    static func floorLabel(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func pill(
        _ title: String,
        systemImage: String? = nil,
        isOn: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            pillLabel(title, systemImage: systemImage, isOn: isOn, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func pillLabel(
        _ title: String,
        systemImage: String?,
        isOn: Bool,
        tint: Color
    ) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
        }
        .font(MapTheme.pillFont)
        .foregroundStyle(isOn ? MapTheme.background : tintedText(tint))
        .padding(.horizontal, 11)
        .frame(height: MapTheme.pillHeight)
        .background(
            isOn ? tint : MapTheme.control,
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(isOn ? Color.clear : MapTheme.hairline, lineWidth: 1)
        )
    }

    /// An off pill carries its own colour only where that colour means
    /// something — curated red. Everything else is quiet grey until chosen.
    private func tintedText(_ tint: Color) -> Color {
        tint == MapTheme.curated ? MapTheme.curated : MapTheme.secondaryText
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.listSpots.isEmpty {
                    Text(emptyMessage)
                        .font(MapTheme.rowDetailFont)
                        .foregroundStyle(MapTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MapTheme.gutter)
                }
                ForEach(model.listSpots) { spot in
                    Button {
                        selectedSpot = spot
                    } label: {
                        SpotRowView(
                            spot: spot,
                            distanceMetres: model.listOrigin.distance(to: spot.coordinate)
                        )
                    }
                    .buttonStyle(.plain)
                    Rectangle()
                        .fill(MapTheme.rowRule)
                        .frame(height: 1)
                        .padding(.leading, 63)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var emptyMessage: String {
        if model.filters.litNow {
            return "Nothing here is in the sun right now. Turn off *Lit now* to see the rest."
        }
        if !model.searchText.isEmpty {
            return "No spot here matches “\(model.searchText)”."
        }
        return model.isCityStored
            ? "No spots in this part of the map. Pan, or lower the score floor."
            : "No spots stored for here yet. Open the city chip to download one."
    }
}

/// A row of the ranked list: glyph, name, the score as prose, distance.
struct SpotRowView: View {
    let spot: Spot
    let distanceMetres: Double

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(MapTheme.markerFill(score: spot.score, curated: spot.curated))
                Image(systemName: MapTheme.symbol(for: spot.kind))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(spot.curated ? MapTheme.background : MapTheme.primaryText)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .font(MapTheme.rowTitleFont)
                    .foregroundStyle(MapTheme.primaryText)
                    .lineLimit(1)
                Text(SpotProse.scoreSummary(for: spot))
                    .font(MapTheme.rowDetailFont)
                    .foregroundStyle(MapTheme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(SpotProse.distance(metres: distanceMetres))
                .font(MapTheme.rowDistanceFont)
                .foregroundStyle(MapTheme.secondaryText)
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

extension String {
    /// Pill and badge labels are sentence case; the prose they come from is not.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

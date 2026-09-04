import MapKit
import SwiftUI
import TDMCore
import TDMPersistence
import TDMSpots
import TDMWeather

/// The first tab: a full-bleed dark map, a city chip over it, and a draggable
/// sheet at three detents below (`docs/SPEC-map.md`, "Layout").
///
/// The map answers one question — *where should I walk from here?* — so nothing
/// competes with it: the chrome is three small floating controls and a sheet
/// that gets out of the way.
public struct MapView: View {
    @State private var model: MapViewModel
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheetHeight: CGFloat = MapView.collapsedHeight
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var selectedSpot: Spot?
    @State private var pendingPin: PinDrop?
    @State private var isShowingCityPicker = false
    @State private var isShowingSettings = false

    /// Hands a spot to the Light tab, which opens pre-filled for it.
    private let openLight: (SpotHandoff) -> Void

    /// The collapsed height: the handle, the search field and the pills, which
    /// is what `design/Map.dc.html` shows above the list.
    static let collapsedHeight: CGFloat = 170
    /// `docs/SPEC-map.md`, "Layout": the top floating controls "sit at the top
    /// because the sheet is persistent" — even at its tallest, real headroom is
    /// left so the city chip and sun toggle stay reachable.
    private static let largeHeightInset: CGFloat = 96
    /// A floor under `geometry.safeAreaInsets.bottom` for the sheet's own
    /// bottom clearance — the classic docked tab bar's content height, before
    /// the home indicator. `sheetContainer` pads by whichever of this or the
    /// real inset is larger.
    private static let minimumTabBarHeight: CGFloat = 49

    public init(
        store: any SpotStore,
        bundles: BundleService? = nil,
        gearStore: GearStore? = nil,
        weather: WeatherService? = nil,
        location: LocationProvider = LocationProvider(),
        openLight: @escaping (SpotHandoff) -> Void = { _ in }
    ) {
        _model = State(
            initialValue: MapViewModel(
                store: store,
                bundles: bundles,
                gearStore: gearStore,
                weather: weather,
                location: location
            )
        )
        self.openLight = openLight
    }

    /// `docs/SPEC-map.md`, "Layout": the browse sheet is persistent, not a
    /// modal — it and the tab bar both own the bottom of the screen at once.
    /// `.sheet(isPresented: .constant(true))` used to stand in for that, but a
    /// real `.sheet` always presents in a layer above the *entire window*, tab
    /// bar included, and fights the `TabView`'s own presentation lifecycle
    /// across a tab switch — which is what left a stale spot-detail card
    /// stuck on screen after handing a spot to the Light tab, and hid the tab
    /// bar outright on first launch. This is an ordinary view in `MapView`'s
    /// own tree instead, sized by hand, so it can never cover chrome it isn't
    /// drawn over.
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ZStack(alignment: .top) {
                    mapSurface
                    overlay
                }
                .background(MapTheme.ground)

                sheetContainer(
                    availableHeight: geometry.size.height,
                    tabBarInset: geometry.safeAreaInsets.bottom
                )
            }
        }
        .task { await model.start() }
        .sheet(item: $pendingPin) { drop in
            PinEditorView(
                coordinate: drop.coordinate,
                streetBearingDegrees: model.pinBearingDegrees
            ) { pin in
                Task { await model.savePin(pin) }
            }
        }
        .sheet(isPresented: $isShowingCityPicker) {
            CityPickerView(model: model)
        }
        .sheet(isPresented: $isShowingSettings) {
            MapSettingsView(model: model)
        }
    }

    // MARK: The persistent sheet

    /// `tabBarInset` is `geometry.safeAreaInsets.bottom` measured before this
    /// view's own content has a chance to ignore any safe area — a floating,
    /// translucent tab bar (iOS 18+) does not necessarily reserve its full
    /// visual height as a safe-area inset the way a docked one always did, so
    /// this is padded rather than trusted outright: better a few points of
    /// unused gap above the bar than a list row rendering behind it.
    private func sheetContainer(availableHeight: CGFloat, tabBarInset: CGFloat) -> some View {
        let heights = detentHeights(availableHeight: availableHeight)
        let liveHeight = (sheetHeight - dragTranslation).clamped(to: heights.collapsed...heights.large)
        let clearance = max(tabBarInset, Self.minimumTabBarHeight) + 12

        return VStack(spacing: 0) {
            dragHandle(heights: heights)
            MapSheetView(
                model: model,
                selectedSpot: $selectedSpot,
                openLight: openLight,
                openSettings: { isShowingSettings = true }
            )
        }
        .frame(height: liveHeight)
        .background(MapTheme.sheet)
        .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        .padding(.bottom, clearance)
    }

    /// Only the handle responds to the drag — the sheet's own content is a
    /// search field and a scrolling list, and a whole-sheet drag gesture would
    /// fight both of them for the same touch.
    private func dragHandle(heights: SheetHeights) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(MapTheme.handle)
            .frame(width: 36, height: 4)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let dragged = (sheetHeight - value.translation.height)
                            .clamped(to: heights.collapsed...heights.large)
                        withAnimation(.easeOut(duration: 0.22)) {
                            sheetHeight = heights.nearest(to: dragged)
                        }
                    }
            )
    }

    private struct SheetHeights {
        let collapsed: CGFloat
        let medium: CGFloat
        let large: CGFloat

        func nearest(to height: CGFloat) -> CGFloat {
            [collapsed, medium, large].min { abs($0 - height) < abs($1 - height) } ?? collapsed
        }
    }

    private func detentHeights(availableHeight: CGFloat) -> SheetHeights {
        SheetHeights(
            collapsed: Self.collapsedHeight,
            medium: availableHeight * 0.5,
            large: max(availableHeight - Self.largeHeightInset, availableHeight * 0.5)
        )
    }

    // MARK: The map

    private var mapSurface: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                ForEach(model.annotations.clusters) { cluster in
                    Annotation(
                        cluster.representative.name,
                        coordinate: cluster.coordinate.locationCoordinate,
                        anchor: .center
                    ) {
                        SpotMarkerView(cluster: cluster)
                            .onTapGesture { tapped(cluster) }
                    }
                    .annotationTitles(.hidden)
                }
            }
            // Points of interest are Apple's idea of what matters; this map has
            // its own, and two sets of pins would fight.
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { }
            .onMapCameraChange(frequency: .continuous) { context in
                model.regionChanged(to: BoundingBox(context.region))
            }
            .gesture(longPress(proxy: proxy))
            .ignoresSafeArea()
        }
    }

    /// A long press drops a pin where the finger was, which needs the point as
    /// well as the gesture — hence the sequence rather than a plain long press.
    private func longPress(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.55)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case let .second(true, drag?) = value,
                      let coordinate = proxy.convert(drag.location, from: .local)
                else { return }
                pendingPin = PinDrop(
                    coordinate: Coordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
            }
    }

    private func tapped(_ cluster: SpotCluster) {
        if cluster.isSingle {
            selectedSpot = cluster.representative
        } else {
            // A bubble is a promise that there is something under it: zoom in
            // rather than open one of several arbitrarily.
            withAnimation {
                camera = .region(
                    MKCoordinateRegion(
                        center: cluster.coordinate.locationCoordinate,
                        latitudinalMeters: 1_200,
                        longitudinalMeters: 1_200
                    )
                )
            }
        }
    }

    // MARK: Chrome

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                cityChip
                Spacer(minLength: 12)
                VStack(spacing: 12) {
                    sunToggle
                    if model.isSunOverlayVisible, let sun = model.sun {
                        SunDialView(azimuthDegrees: sun.azimuthDegrees)
                    }
                    recentreButton
                }
            }
            .padding(.horizontal, MapTheme.gutter)

            if let note = model.refreshError {
                banner(note, colour: MapTheme.curated)
            } else if let prompt = model.downloadPrompt, let entry = model.indexEntry {
                downloadBanner(prompt, entry: entry)
            } else if let prompt = model.updatePrompt, let entry = model.updateEntry {
                downloadBanner(prompt, entry: entry)
            } else if let note = model.emptyAreaNote {
                banner(note, colour: MapTheme.tertiaryText)
            }

            Spacer(minLength: 0)
            attribution
        }
        .padding(.top, 8)
    }

    private var cityChip: some View {
        Button {
            isShowingCityPicker = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MapTheme.accent)
                Text(model.cityChipTitle ?? "No city")
                    .font(MapTheme.chipFont)
                    .foregroundStyle(MapTheme.primaryText)
                if let count = model.cityChipCount {
                    Text("\(count)")
                        .font(MapTheme.chipCountFont)
                        .foregroundStyle(MapTheme.tertiaryText)
                }
                if model.isCityStored {
                    Text("OFFLINE")
                        .font(MapTheme.badgeFont)
                        .kerning(0.72)
                        .foregroundStyle(MapTheme.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            MapTheme.offline,
                            in: RoundedRectangle(cornerRadius: MapTheme.badgeRadius)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MapTheme.floating, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                    .stroke(MapTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("City picker")
    }

    private var sunToggle: some View {
        floatingButton(
            systemImage: "sun.max",
            tint: model.isSunOverlayVisible ? MapTheme.background : MapTheme.accent,
            fill: model.isSunOverlayVisible ? MapTheme.accent : MapTheme.floating,
            label: "Show the sun's direction"
        ) {
            model.isSunOverlayVisible.toggle()
        }
    }

    private var recentreButton: some View {
        floatingButton(
            systemImage: "location",
            tint: MapTheme.accent,
            fill: MapTheme.floating,
            label: "Recentre on me"
        ) {
            withAnimation { camera = .userLocation(fallback: .automatic) }
        }
    }

    private func floatingButton(
        systemImage: String,
        tint: Color,
        fill: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(tint)
                .frame(width: MapTheme.floatingSize, height: MapTheme.floatingSize)
                .background(fill, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                        .stroke(MapTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func banner(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(MapTheme.rowDetailFont)
            .foregroundStyle(colour)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MapTheme.floating, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                    .stroke(MapTheme.hairline, lineWidth: 1)
            )
            .padding(.horizontal, MapTheme.gutter)
            .padding(.top, 10)
    }

    private func downloadBanner(_ prompt: String, entry: CityIndexEntry) -> some View {
        Button {
            Task { await model.download(entry) }
        } label: {
            HStack(spacing: 8) {
                Text(prompt)
                    .font(MapTheme.rowDetailFont)
                    .foregroundStyle(MapTheme.primaryText)
                    .multilineTextAlignment(.leading)
                if model.isDownloading {
                    ProgressView().controlSize(.mini).tint(MapTheme.accent)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(MapTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MapTheme.floating, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                    .stroke(MapTheme.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 10)
    }

    /// Shown on the map surface itself, not in a settings screen: the licence
    /// asks for it where the data is used.
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.attributionLines, id: \.self) { line in
                Text(line)
                    .font(MapTheme.creditFont)
                    .foregroundStyle(MapTheme.quaternaryText)
            }
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.bottom, 6)
    }
}

/// The solar azimuth dial of `design/Map.dc.html`: a 32 pt disc with a ray
/// pointing where the sun is.
struct SunDialView: View {
    let azimuthDegrees: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(MapTheme.background.opacity(0.85))
                .overlay(Circle().stroke(MapTheme.hairline, lineWidth: 1))
            // North is up on the map, and azimuth is measured clockwise from it.
            Path { path in
                path.move(to: CGPoint(x: 16, y: 16))
                path.addLine(to: CGPoint(x: 16, y: 3))
            }
            .stroke(MapTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(azimuthDegrees), anchor: .center)
            Circle()
                .fill(MapTheme.accent)
                .frame(width: 4, height: 4)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel("Sun at \(Int(azimuthDegrees.rounded()))°")
    }
}

extension Coordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A long-press waiting for the pin editor. Identity is the press, not the
/// coordinate: pressing the same doorway twice should open the editor twice.
struct PinDrop: Identifiable {
    let id = UUID()
    let coordinate: Coordinate
}

extension Comparable {
    /// The sheet's height while dragging is a live subtraction that can
    /// overshoot either end before the drag has finished; clamp it to the
    /// collapsed…large range on every frame rather than only at rest.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension BoundingBox {
    /// The visible rectangle, as the store's bounding-box query wants it.
    init(_ region: MKCoordinateRegion) {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        self.init(
            minLat: region.center.latitude - halfLat,
            minLon: region.center.longitude - halfLon,
            maxLat: region.center.latitude + halfLat,
            maxLon: region.center.longitude + halfLon
        )
    }
}

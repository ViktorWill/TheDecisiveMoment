import SwiftUI
import TDMCore
import TDMLight
import TDMSpots
import TDMWeather

/// One spot, in full (`docs/SPEC-map.md`, "Spot detail").
///
/// The score is prose and never a bare number, the curated note is unclipped
/// because it is the most valuable thing on the screen, and every photo carries
/// its author and licence — that last one is a licence condition, not a design
/// preference.
struct SpotDetailView: View {
    let spot: Spot
    let origin: Coordinate
    let profile: GearProfile?
    let weather: WeatherService?
    let openLight: (SpotHandoff) -> Void
    let deletePin: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var marks = SpotMarksStore()
    @State private var isSaved = false
    @State private var isVisited = false
    @State private var personalNote = ""
    @State private var personalNoteDisplay: String?
    @State private var isEditingNote = false
    private let now = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                lightStrip
                if let note = spot.note, !note.isEmpty {
                    section("Note") {
                        Text(note)
                            .font(MapTheme.noteFont)
                            .lineSpacing(4)
                            .foregroundStyle(MapTheme.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let personal = personalNoteDisplay {
                    section("Your note") {
                        Text(personal)
                            .font(MapTheme.noteFont)
                            .lineSpacing(4)
                            .foregroundStyle(MapTheme.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let hours = spot.bestHours, !hours.isEmpty {
                    bestHours(hours)
                }
                if !spot.photos.isEmpty {
                    photos
                }
                if spot.sources.contains(.local) {
                    localOnlyNote
                }
                actions
            }
            .padding(.bottom, 30)
        }
        .background(MapTheme.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isSaved = marks.isSaved(spot.id)
            isVisited = marks.isVisited(spot.id)
            personalNoteDisplay = marks.note(spot.id)
            personalNote = personalNoteDisplay ?? ""
        }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorView(text: $personalNote) {
                marks.setNote(personalNote, for: spot.id)
                personalNoteDisplay = marks.note(spot.id)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(spot.name)
                    .font(MapTheme.titleFont)
                    .foregroundStyle(MapTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(SpotProse.distance(metres: distanceMetres))
                        .font(MapTheme.distanceFont)
                        .foregroundStyle(MapTheme.primaryText)
                    Text(SpotProse.walkingTime(metres: distanceMetres))
                        .font(.system(size: 11))
                        .foregroundStyle(MapTheme.tertiaryText)
                }
            }

            HStack(spacing: 7) {
                if spot.curated {
                    Text("Curated")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(MapTheme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            MapTheme.curated,
                            in: RoundedRectangle(cornerRadius: MapTheme.badgeRadius)
                        )
                }
                // The score, as prose. Never the number itself.
                Text(SpotProse.detailSummary(for: spot))
                    .font(.system(size: 12))
                    .foregroundStyle(MapTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 11)
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 12)
    }

    private var distanceMetres: Double { origin.distance(to: spot.coordinate) }

    private var lightStrip: some View {
        SpotLightStrip(
            spot: spot,
            profile: profile,
            weather: weather,
            now: now
        ) {
            openLight(SpotHandoff(spot: spot))
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 16)
    }

    /// A titled block, 18 pt below the last one — the rhythm of
    /// `design/SpotDetail.dc.html`.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(MapTheme.sectionLabelFont)
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(MapTheme.tertiaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 18)
    }

    // MARK: Best hours

    /// A 24-hour bar with the current hour marked, `design/SpotDetail.dc.html`.
    private func bestHours(_ hours: [Int]) -> some View {
        let lit = Set(hours)
        let currentHour = Calendar.current.component(.hour, from: now)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Best hours")
                    .font(MapTheme.sectionLabelFont)
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(MapTheme.tertiaryText)
                Spacer()
                Text("now \(String(format: "%02d:00", currentHour))")
                    .font(MapTheme.tickFont)
                    .foregroundStyle(MapTheme.accent)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(lit.contains(hour) ? MapTheme.accent : MapTheme.barOff)
                        .frame(height: hour == currentHour ? 15 : 8)
                }
            }
            .padding(.top, 10)
            .accessibilityElement()
            .accessibilityLabel("Best hours")
            .accessibilityValue(hours.map { String(format: "%02d:00", $0) }.joined(separator: ", "))

            HStack {
                ForEach(["00", "06", "12", "18", "23"], id: \.self) { tick in
                    Text(tick)
                        .font(MapTheme.tickFont)
                        .foregroundStyle(MapTheme.quaternaryText)
                    if tick != "23" { Spacer() }
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 18)
    }

    // MARK: Photos

    /// Author and licence sit under every thumbnail. Required, not optional —
    /// `docs/DATA-BUNDLES.md` ("Attribution").
    private var photos: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                ForEach(spot.photos.prefix(2), id: \.thumbURL) { photo in
                    VStack(alignment: .leading, spacing: 5) {
                        AsyncImage(url: URL(string: photo.thumbURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            MapTheme.plate
                        }
                        .frame(height: 92)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: MapTheme.tileRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: MapTheme.tileRadius)
                                .stroke(MapTheme.hairline, lineWidth: 1)
                        )
                        Text("\(photo.author) · \(photo.license)")
                            .font(MapTheme.creditFont)
                            .foregroundStyle(MapTheme.quaternaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 18)
    }

    /// Pins are on this device and nowhere else in v1. The natural assumption is
    /// that they sync, so the screen says otherwise.
    private var localOnlyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 12))
            Text("Your pin. Stored on this device only — export from settings to keep a copy.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MapTheme.tertiaryText)
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 18)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: openDirections) {
                HStack(spacing: 7) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 15))
                    Text("Directions")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(MapTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: MapTheme.actionHeight)
                .background(MapTheme.accent, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
            }
            .buttonStyle(.plain)

            squareAction(
                systemImage: isSaved ? "bookmark.fill" : "bookmark",
                label: "Save",
                isOn: isSaved
            ) {
                marks.toggleSaved(spot.id)
                isSaved = marks.isSaved(spot.id)
            }

            squareAction(
                systemImage: isVisited ? "checkmark.circle.fill" : "checkmark",
                label: "Mark as visited",
                isOn: isVisited
            ) {
                marks.toggleVisited(spot.id)
                isVisited = marks.isVisited(spot.id)
            }

            squareAction(systemImage: "square.and.pencil", label: "Add a note", isOn: false) {
                isEditingNote = true
            }

            if spot.sources.contains(.local) {
                squareAction(systemImage: "trash", label: "Delete this pin", isOn: false) {
                    deletePin(spot.id)
                    dismiss()
                }
            }
        }
        .padding(.horizontal, MapTheme.gutter)
        .padding(.top, 24)
    }

    private func squareAction(
        systemImage: String,
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(isOn ? MapTheme.accent : MapTheme.secondaryText)
                .frame(width: MapTheme.actionHeight, height: MapTheme.actionHeight)
                .background(MapTheme.control, in: RoundedRectangle(cornerRadius: MapTheme.chipRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: MapTheme.chipRadius)
                        .stroke(MapTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Handing off to Maps rather than drawing a route: this app is not a
    /// navigator, and pretending otherwise would be a worse one. `dirflg=w`
    /// because the answer to "where should I walk from here?" is a walk.
    private func openDirections() {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(spot.lat),\(spot.lon)"),
            URLQueryItem(name: "q", value: spot.name),
            URLQueryItem(name: "dirflg", value: "w")
        ]
        guard let url = components.url else { return }
        openURL(url)
    }
}

/// A personal note about a spot. Local, keyed by spot id, and untouched by a
/// bundle update.
struct NoteEditorView: View {
    @Binding var text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(MapTheme.noteFont)
                .foregroundStyle(MapTheme.bodyText)
                .scrollContentBackground(.hidden)
                .padding(MapTheme.gutter)
                .background(MapTheme.sheet)
                .navigationTitle("Your note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .presentationBackground(MapTheme.sheet)
    }
}

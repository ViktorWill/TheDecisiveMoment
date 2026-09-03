import SwiftUI
import TDMCore
import TDMSpots

/// Writing a plan down: what, where, when, and how long for.
///
/// Visibility is shown and not offered. Every v1 session is `.private`, and a
/// picker whose other two options do nothing would be a promise the app cannot
/// keep — `docs/SPEC-community.md`.
struct SessionEditorView: View {
    @State private var draft: ShootSession
    let model: CommunityViewModel
    let isNew: Bool
    let onSave: (ShootSession) -> Void
    let onDelete: (ShootSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingSpot = false
    @State private var anchorName: String?

    init(
        session: ShootSession,
        model: CommunityViewModel,
        isNew: Bool,
        onSave: @escaping (ShootSession) -> Void,
        onDelete: @escaping (ShootSession) -> Void
    ) {
        _draft = State(initialValue: session)
        _anchorName = State(initialValue: model.name(forAnchor: session.spotId))
        self.model = model
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// The lengths a walk actually takes. A stepper in minutes would be more
    /// precision than anyone has about a Saturday morning.
    private static let durations: [TimeInterval] = [
        1800, 3600, 5400, 7200, 10800, 14400
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .accessibilityLabel("Title")

                    Picker("City", selection: $draft.cityId) {
                        ForEach(model.cities) { city in
                            Text(city.name).tag(city.id)
                        }
                        if !model.cities.contains(where: { $0.id == draft.cityId }) {
                            Text(model.cityName(draft.cityId)).tag(draft.cityId)
                        }
                    }
                } header: {
                    Text("The plan")
                }

                Section {
                    DatePicker("Starts", selection: $draft.startsAt)
                    Picker("Length", selection: $draft.duration) {
                        ForEach(Self.durations, id: \.self) { seconds in
                            Text(CommunityPhrasing.duration(seconds)).tag(seconds)
                        }
                    }
                } header: {
                    Text("When")
                }

                spotSection

                Section {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Notes")
                } header: {
                    Text("Notes")
                }

                Section {
                    LabeledContent("Visibility") {
                        Text("Private")
                            .foregroundStyle(MapTheme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Visibility, private")
                } footer: {
                    Text(CommunityPhrasing.explanation(for: .private)
                        + " Sharing a plan with a city arrives with the backend, and it will be a choice you make each time.")
                        .scaledFont(size: 11)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete(draft)
                            dismiss()
                        } label: {
                            Label("Delete this plan", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .navigationTitle(isNew ? "New plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(!trimmed.isValid)
                }
            }
            .sheet(isPresented: $isPickingSpot) {
                SpotAnchorPickerView(store: model.store, cityId: draft.cityId) { spot in
                    draft.spotId = spot.id
                    draft.meetingPoint = spot.coordinate
                    anchorName = spot.name
                    if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.title = spot.name
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(MapTheme.sheet)
    }

    private var spotSection: some View {
        Section {
            Button {
                isPickingSpot = true
            } label: {
                LabeledContent("Spot") {
                    Text(anchorName ?? "None")
                        .foregroundStyle(anchorName == nil ? MapTheme.tertiaryText : MapTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Anchors this plan to a spot from the map")

            if draft.spotId != nil {
                Button("Remove the anchor") {
                    draft.spotId = nil
                    anchorName = nil
                }
            }

            Text(String(format: "Meeting point %.5f, %.5f", draft.meetingPoint.latitude, draft.meetingPoint.longitude))
                .scaledFont(size: 9, monospacedDigit: true)
                .foregroundStyle(MapTheme.tertiaryText)
                .accessibilityLabel(
                    String(
                        format: "Meeting point, latitude %.3f, longitude %.3f",
                        draft.meetingPoint.latitude,
                        draft.meetingPoint.longitude
                    )
                )
        } header: {
            Text("Where")
        } footer: {
            // The rule that survives into phase 3, so it is stated in v1.
            Text("Meet in public places.")
                .scaledFont(size: 11)
        }
    }

    private var trimmed: ShootSession {
        var session = draft
        session.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return session
    }
}

/// Picking the spot a plan is anchored to: whatever is stored for that city,
/// searched offline, own pins included.
struct SpotAnchorPickerView: View {
    let store: any SpotStore
    let cityId: String
    let onPick: (Spot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var spots: [Spot] = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            List {
                if spots.isEmpty {
                    ContentUnavailableView {
                        Label(hasLoaded ? "Nothing to anchor to" : "Looking", systemImage: "mappin.slash")
                    } description: {
                        Text(
                            searchText.isEmpty
                                ? "Download this city on the Map tab, or drop a pin, and it will show up here."
                                : "No spot in this city matches “\(searchText)”."
                        )
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(spots) { spot in
                        Button {
                            onPick(spot)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spot.name)
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundStyle(MapTheme.primaryText)
                                Text(SpotProse.label(for: spot.kind).capitalizedFirst)
                                    .scaledFont(size: 11)
                                    .foregroundStyle(MapTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .searchable(text: $searchText, prompt: "Search this city")
            .navigationTitle("Anchor to a spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: searchText) { await load() }
        }
    }

    /// Offline, always: this reads the stored bundle and the user's pins, and
    /// never a network.
    private func load() async {
        let query = SpotQuery(searchText: searchText, alwaysIncludeCurated: true)
        spots = Array(((try? await store.spots(in: cityId, matching: query)) ?? []).prefix(60))
        hasLoaded = true
    }
}

/// The local photographer: a name so a plan has an owner, and the gear line
/// that will introduce you once there is anyone to introduce you to.
struct ProfileEditorView: View {
    @State private var draft: Photographer
    let onSave: (Photographer) -> Void

    @Environment(\.dismiss) private var dismiss

    init(profile: Photographer, onSave: @escaping (Photographer) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.displayName)
                    TextField(
                        "Gear, e.g. M6 · 35mm",
                        text: Binding(
                            get: { draft.gearSummary ?? "" },
                            set: { draft.gearSummary = $0.isEmpty ? nil : $0 }
                        )
                    )
                } footer: {
                    Text("Stays on this device. There is no account and nothing is uploaded.")
                        .scaledFont(size: 11)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(cleaned)
                        dismiss()
                    }
                    .disabled(!cleaned.isValid)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(MapTheme.sheet)
    }

    private var cleaned: Photographer {
        var profile = draft
        profile.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.gearSummary = draft.gearSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.gearSummary?.isEmpty == true { profile.gearSummary = nil }
        return profile
    }
}

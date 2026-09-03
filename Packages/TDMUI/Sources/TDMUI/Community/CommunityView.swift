import SwiftUI
import TDMCore
import TDMSpots

/// The third tab: your own shooting plans, and an honest account of what this
/// section is going to become.
///
/// There is no feed here and no invented people — `docs/SPEC-community.md`. The
/// list is what you wrote down, it is stored on this device, and every session
/// is private.
public struct CommunityView: View {
    @State private var model: CommunityViewModel
    @State private var editing: ShootSession?
    @State private var isEditingProfile = false

    public init(model: CommunityViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            List {
                if model.sessions.isEmpty {
                    emptyState
                } else {
                    plansSection
                }
                whatThisBecomes
                profileSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MapTheme.background)
            .navigationTitle("Community")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { startNewSession() } label: {
                        Label("Plan a walk", systemImage: "plus")
                    }
                    .disabled(model.profile == nil)
                    .accessibilityLabel("Plan a walk")
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $editing) { session in
                SessionEditorView(
                    session: session,
                    model: model,
                    isNew: !model.sessions.contains { $0.id == session.id }
                ) { edited in
                    Task { await model.save(edited) }
                } onDelete: { removed in
                    Task { await model.delete(removed) }
                }
            }
            .sheet(isPresented: $isEditingProfile) {
                if let profile = model.profile {
                    ProfileEditorView(profile: profile) { edited in
                        Task { await model.saveProfile(edited) }
                    }
                }
            }
            .alert(
                "Could not save",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.dismissError() } }
                )
            ) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var plansSection: some View {
        Section {
            ForEach(model.sessions) { session in
                Button { editing = session } label: {
                    SessionRowView(session: session, anchorName: model.name(forAnchor: session.spotId))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await model.delete(session) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Your plans")
        } footer: {
            Text("Stored on this device. Nobody else can see these.")
                .scaledFont(size: 11)
        }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label("No plans yet", systemImage: "figure.walk")
            } description: {
                Text("Write down where you are going and when. Anchor it to a spot from the Map tab, or leave it loose.")
            } actions: {
                Button("Plan a walk") { startNewSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.profile == nil)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var whatThisBecomes: some View {
        Section {
            Label {
                Text("Later, this is where you will find other photographers shooting the same city — who is going out, where, and whether you can come.")
            } icon: {
                Image(systemName: "person.2")
            }
            .scaledFont(size: 11)
            .foregroundStyle(MapTheme.secondaryText)

            Label {
                Text("Until there are people in it, showing a feed would be pretending. So this tab is your own plan, and nothing is uploaded.")
            } icon: {
                Image(systemName: "lock")
            }
            .scaledFont(size: 11)
            .foregroundStyle(MapTheme.secondaryText)
        } header: {
            Text("What this becomes")
        }
    }

    private var profileSection: some View {
        Section {
            Button {
                isEditingProfile = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.profile?.displayName ?? Photographer.defaultDisplayName)
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(MapTheme.primaryText)
                        Text(model.profile?.gearSummary ?? "Add the gear you usually carry")
                            .scaledFont(size: 11)
                            .foregroundStyle(MapTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MapTheme.tertiaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edits the name and gear on this device")
        } header: {
            Text("You")
        } footer: {
            Text("There is no account. This name is only used to say who a plan belongs to.")
                .scaledFont(size: 11)
        }
    }

    /// A draft needs the profile the backend hands back on load, so the button
    /// is disabled until that has arrived rather than swallowing the tap.
    private func startNewSession() {
        editing = model.newSession()
    }
}

/// One plan: what it is called, when it starts, and what it is anchored to.
struct SessionRowView: View {
    let session: ShootSession
    let anchorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(MapTheme.primaryText)

            // Tabular figures: a list of times that jitters as it redraws is
            // harder to scan than one that does not.
            Text(when)
                .scaledFont(size: 11, monospacedDigit: true)
                .foregroundStyle(MapTheme.secondaryText)

            if let anchorName {
                Label(anchorName, systemImage: "mappin.and.ellipse")
                    .scaledFont(size: 11)
                    .foregroundStyle(MapTheme.tertiaryText)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    private var when: String {
        let start = session.startsAt.formatted(date: .abbreviated, time: .shortened)
        return "\(start) · \(CommunityPhrasing.duration(session.duration))"
    }

    private var spokenLabel: String {
        let start = session.startsAt.formatted(date: .abbreviated, time: .shortened)
        var parts = [session.title, "\(start), for \(CommunityPhrasing.spokenDuration(session.duration))"]
        if let anchorName { parts.append("at \(anchorName)") }
        parts.append("private")
        return parts.joined(separator: ", ")
    }
}

/// Words the Community tab needs and the model does not.
enum CommunityPhrasing {
    /// `2 h`, `1 h 30`, `45 min`, as a dial is engraved rather than as a
    /// sentence.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, remainder)
    }

    /// The same length said aloud: `h` is not a word.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let remainder = minutes % 60
        let hourPhrase = hours == 1 ? "1 hour" : "\(hours) hours"
        return remainder == 0 ? hourPhrase : "\(hourPhrase) \(remainder) minutes"
    }

    /// What a visibility setting means, in the plainest words available.
    static func explanation(for visibility: SessionVisibility) -> String {
        switch visibility {
        case .private: "Only you. Stored on this device."
        case .link: "Anyone you send the link to. Not available yet."
        case .city: "Anyone browsing this city. Not available yet."
        }
    }
}

#Preview {
    CommunityView(model: CommunityViewModel(backend: InMemoryCommunityBackend()))
}

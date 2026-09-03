# Spec — Community

The third tab. **Modelled in v1, backed by a server later.** This document covers both, because the
point of writing it now is to make sure the v1 data model does not have to be rewritten when the
backend arrives.

## Why it is deferred

A community feature with no community is an empty screen, and standing up auth, storage and
moderation before there is anyone to talk to is work spent in the wrong order. The Map and Light
features are useful to one person on day one; this one is not useful until there are twenty people
in a city.

So v1 ships the data model, exercised locally and for real, behind a protocol.

## v1 — local only

A *Sessions* list: plans to go out and shoot.

```swift
struct ShootSession: Identifiable, Codable, Sendable {
    let id: UUID
    var cityId: String
    var spotId: String?          // optional anchor into the map
    var title: String
    var startsAt: Date
    var duration: TimeInterval
    var meetingPoint: Coordinate
    var notes: String
    var maxPeople: Int?
    var hostId: Photographer.ID
    var attendeeIds: [Photographer.ID]
    var visibility: Visibility   // .private, .link, .city
}

struct Photographer: Identifiable, Codable, Sendable {
    let id: UUID
    var displayName: String
    var gearSummary: String?     // "M6 · 35mm" — a conversation starter, not a spec sheet
    var bio: String?
    var cities: [String]
}
```

In v1 you can create, edit and delete sessions; they are stored locally, visible only to you, and
usable as a personal shooting plan. `visibility` is present but every session is effectively
`.private`: the tab shows it and does not offer it, because a picker whose other two options do
nothing would be a promise the app cannot keep.

The tab explains what it is going to become. It does not pretend to have people in it, and it does
not show a fake feed.

A plan can be anchored to a spot, which fills in the meeting point and the title from the map. The
anchor is a plain `spotId`, not a reference: a bundle refresh replaces every spot row of a city, and
a plan has to outlive that. An anchored spot that is no longer stored simply loses its name in the
list.

Every session needs a `cityId`, and a device that has downloaded nothing has no city to offer. Those
plans are filed under `elsewhere`, which is a real id with no bundle behind it — refusing to let
someone write a plan down until they have downloaded a map would be an invented obstacle.

There is no account, so the local photographer is a single seeded row named *You*, editable from the
tab. Its `id` is the `hostId` of every session on the device.

## The protocol

```swift
protocol CommunityBackend: Sendable {
    func sessions(in cityId: String, from: Date) async throws -> [ShootSession]
    func sessions(from: Date) async throws -> [ShootSession]
    func create(_ session: ShootSession) async throws -> ShootSession
    func update(_ session: ShootSession) async throws -> ShootSession
    func cancel(id: ShootSession.ID) async throws
    func join(sessionId: ShootSession.ID) async throws
    func leave(sessionId: ShootSession.ID) async throws
    func profile() async throws -> Photographer
    func save(_ profile: Photographer) async throws -> Photographer
}
```

Two methods are not city-scoped and were not in the first draft of this list. `sessions(from:)`
exists because a personal plan spans however many cities the photographer travels to, and asking
them to pick a city before they can see their own list would be an invented step; a server browses
one city at a time, which is what the other method is for. `save(_ profile:)` exists because v1 has
no account to take a display name from.

Errors are a `CommunityError` enum — session not found, invalid session, invalid profile, session
full, already attending, storage failed — so the UI can say what happened rather than print a type
name.

v1 ships `LocalCommunityBackend` (SwiftData), and `InMemoryCommunityBackend` in `TDMCore` for
previews, tests and a device whose store will not open: losing a plan when the app quits is bad,
refusing to draw the tab is worse. Phase 3 adds `SupabaseCommunityBackend`. The views bind to the
protocol, so the swap does not touch the UI.

## Phase 3 — the backend

Supabase, chosen for Postgres with row-level security, built-in auth, and a free tier that comfortably
covers a few dozen people.

Tables mirror the structs: `photographers`, `sessions`, `attendees`. Row-level security is the
important part — a session is readable when `visibility = 'city'`, or the reader is the host, or the
reader is an attendee.

Auth: Sign in with Apple only. No passwords to leak, no email flow to build, and it matches the
audience.

### What must be designed before any of it ships

Not implementation details — the reasons a feature like this goes wrong:

- **Meeting a stranger from an app is a physical-safety question.** Meeting points are public places
  only. Report and block from day one, not later. No precise live location sharing, ever.
- **Broadcasting where a person will be at a specific time is sensitive**, particularly for the
  people most likely to be harassed. Default visibility is `.private`. `.city` is an explicit,
  informed choice with a plain-language explanation of who can see it.
- **Moderation needs an owner.** At this scale that is you, with a report queue and the ability to
  remove a session or a person. Automated moderation is not warranted and would not work.
- **Your own map pins stay private unless explicitly shared.** Sharing is per-pin and opt-in. The
  local-only promise made in v1 must not be quietly revoked by a later release — if that changes, it
  changes with a prompt, not a migration.

These get a written privacy review before phase 3 starts. The architecture note in
[ARCHITECTURE.md](ARCHITECTURE.md#privacy) records that v1 sends nothing off the device; the moment
that stops being true, it needs to be a deliberate, documented decision.

## What it is not

Not a feed, not follows, not likes, not photo hosting. There are enough of those and none of them
help you find someone to walk around Kreuzberg with on Saturday morning. Keep it to: who is shooting,
where, when, and can I come.

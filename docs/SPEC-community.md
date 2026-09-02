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
`.private`.

The tab explains what it is going to become. It does not pretend to have people in it, and it does
not show a fake feed.

## The protocol

```swift
protocol CommunityBackend: Sendable {
    func sessions(in cityId: String, from: Date) async throws -> [ShootSession]
    func create(_ session: ShootSession) async throws -> ShootSession
    func update(_ session: ShootSession) async throws -> ShootSession
    func cancel(id: ShootSession.ID) async throws
    func join(sessionId: ShootSession.ID) async throws
    func leave(sessionId: ShootSession.ID) async throws
    func profile() async throws -> Photographer
}
```

v1 ships `LocalCommunityBackend` (SwiftData). Phase 3 adds `SupabaseCommunityBackend`. The views bind
to the protocol, so the swap does not touch the UI.

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

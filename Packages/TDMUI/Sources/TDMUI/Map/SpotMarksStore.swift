import Foundation
import TDMSpots

/// What the photographer has done with a spot: saved it, walked to it, written
/// something about it.
///
/// Keyed by spot id and stored on the device, so it survives a bundle update —
/// which is the whole reason ids have to be stable (`docs/SPEC-map.md`,
/// "Spot detail"). It is a preference-sized amount of data about *the user*
/// rather than about the city, so it lives in `UserDefaults` and is never
/// touched by an import.
struct SpotMarksStore {
    static let savedKey = "map.saved.v1"
    static let visitedKey = "map.visited.v1"
    static let notesKey = "map.notes.v1"

    // `UserDefaults` is thread-safe by documented contract but predates
    // `Sendable`; `nonisolated(unsafe)` records that the runtime guarantee,
    // not a missing check, is what makes this safe.
    nonisolated(unsafe) var defaults: UserDefaults = .standard

    func isSaved(_ id: String) -> Bool { ids(Self.savedKey).contains(id) }
    func isVisited(_ id: String) -> Bool { ids(Self.visitedKey).contains(id) }

    func note(_ id: String) -> String? {
        let notes = defaults.dictionary(forKey: Self.notesKey) as? [String: String]
        let note = notes?[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (note?.isEmpty ?? true) ? nil : note
    }

    func toggleSaved(_ id: String) { toggle(id, key: Self.savedKey) }
    func toggleVisited(_ id: String) { toggle(id, key: Self.visitedKey) }

    func setNote(_ text: String?, for id: String) {
        var notes = (defaults.dictionary(forKey: Self.notesKey) as? [String: String]) ?? [:]
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            notes[id] = trimmed
        } else {
            notes[id] = nil
        }
        defaults.set(notes, forKey: Self.notesKey)
    }

    private func ids(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func toggle(_ id: String, key: String) {
        var current = ids(key)
        if current.contains(id) { current.remove(id) } else { current.insert(id) }
        defaults.set(Array(current).sorted(), forKey: key)
    }
}

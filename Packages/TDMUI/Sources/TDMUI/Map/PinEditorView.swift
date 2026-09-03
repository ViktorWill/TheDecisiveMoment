import SwiftUI
import TDMCore
import TDMSpots

/// The sheet a long press opens: name, kind, openness, tags, note, and the
/// street bearing pre-filled from the device heading where there is one
/// (`docs/SPEC-map.md`, "Your own pins").
struct PinEditorView: View {
    let coordinate: Coordinate
    /// From the compass, already folded into the 0…180 a street axis takes.
    let streetBearingDegrees: Double?
    let onSave: (Spot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: SpotKind = .street
    @State private var openness: Openness = .open
    @State private var tagText = ""
    @State private var note = ""
    @State private var useHeading = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(SpotKind.allCases, id: \.self) { kind in
                            Text(SpotProse.label(for: kind).capitalizedFirst).tag(kind)
                        }
                    }
                    Picker("Sky", selection: $openness) {
                        ForEach(Openness.allCases, id: \.self) { value in
                            Text(SpotProse.label(for: value).capitalizedFirst).tag(value)
                        }
                    }
                } header: {
                    Text("The place")
                } footer: {
                    Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(MapTheme.tickFont)
                }

                Section {
                    if let streetBearingDegrees {
                        Toggle(isOn: $useHeading) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Street runs \(Int(streetBearingDegrees.rounded()))°")
                                Text("From the compass, which is why *lit now* can answer for this pin.")
                                    .font(MapTheme.creditFont)
                                    .foregroundStyle(MapTheme.tertiaryText)
                            }
                        }
                    } else {
                        Text("No compass reading — this pin will not answer *lit now*.")
                            .font(MapTheme.rowDetailFont)
                            .foregroundStyle(MapTheme.tertiaryText)
                    }
                } header: {
                    Text("Street bearing")
                }

                Section {
                    TextField("Tags, comma separated", text: $tagText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    // The natural assumption is that these sync. They do not.
                    Label(
                        "Pins are stored on this device only. Export them as GeoJSON from map settings.",
                        systemImage: "iphone"
                    )
                    .font(MapTheme.rowDetailFont)
                    .foregroundStyle(MapTheme.tertiaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .navigationTitle("Drop a pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(pin)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(MapTheme.sheet)
    }

    private var pin: Spot {
        LocalPin.make(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            coordinate: coordinate,
            kind: kind,
            openness: openness,
            tags: tags,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            streetBearingDegrees: useHeading ? streetBearingDegrees : nil
        )
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tags: [String] {
        tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

import SwiftUI
import TDMCore
import TDMSpots
import UniformTypeIdentifiers

/// Map settings: the user's own pins, and the export that keeps their data from
/// being trapped (`docs/SPEC-map.md`, "Your own pins").
struct MapSettingsView: View {
    @Bindable var model: MapViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var export: GeoJSONDocument?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.pins.isEmpty {
                        Text("No pins yet. Long-press the map to drop one.")
                            .font(MapTheme.rowDetailFont)
                            .foregroundStyle(MapTheme.tertiaryText)
                    }
                    ForEach(model.pins) { pin in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.name)
                                .font(MapTheme.rowTitleFont)
                                .foregroundStyle(MapTheme.primaryText)
                            Text(SpotProse.scoreSummary(for: pin))
                                .font(MapTheme.rowDetailFont)
                                .foregroundStyle(MapTheme.tertiaryText)
                        }
                        .listRowBackground(MapTheme.sheet)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.deletePin(id: pin.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Your pins")
                } footer: {
                    Text("Pins are stored on this device only in v1. They are never uploaded, and a bundle refresh never removes them.")
                }

                Section {
                    Button("Export as GeoJSON") {
                        Task { await prepareExport() }
                    }
                    .disabled(model.pins.isEmpty)
                    if let exportError {
                        Text(exportError)
                            .font(MapTheme.rowDetailFont)
                            .foregroundStyle(MapTheme.curated)
                    }
                }

                Section {
                    ForEach(model.attributionLines, id: \.self) { line in
                        Text(line)
                            .font(MapTheme.rowDetailFont)
                            .foregroundStyle(MapTheme.tertiaryText)
                    }
                } header: {
                    Text("Attribution")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(MapTheme.sheet)
        .fileExporter(
            isPresented: $isExporting,
            document: export,
            contentType: .json,
            // The exporter appends the type's extension, so the name goes in
            // without one.
            defaultFilename: GeoJSONExport.fileName(date: Date())
                .replacingOccurrences(of: ".geojson", with: "")
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
        }
    }

    private func prepareExport() async {
        do {
            export = GeoJSONDocument(data: try await model.exportPins())
            isExporting = true
        } catch {
            exportError = "Those pins could not be exported."
        }
    }
}

/// The exported file. A `FileDocument` rather than a share sheet so the user
/// picks where it lands — the point of the export is that the data leaves.
struct GeoJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

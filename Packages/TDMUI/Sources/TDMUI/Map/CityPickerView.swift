import SwiftUI
import TDMCore
import TDMSpots

/// Every city the index lists, nearest first, with its size and whether it is
/// on the device (`docs/SPEC-map.md`, "City detection").
///
/// Downloading a city you are not in is a first-class action: you plan a trip
/// on the sofa over Wi-Fi, and you use it in the street with the radio off.
struct CityPickerView: View {
    @Bindable var model: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.indexCities.isEmpty {
                    Text("No city list yet. Connect once and it will be stored for an hour.")
                        .font(MapTheme.rowDetailFont)
                        .foregroundStyle(MapTheme.tertiaryText)
                }
                ForEach(model.indexCities) { entry in
                    row(entry)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MapTheme.sheet)
            .navigationTitle("Cities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await model.resolveCity() }
        }
        .presentationBackground(MapTheme.sheet)
    }

    private func row(_ entry: CityIndexEntry) -> some View {
        let isStored = model.storedCityIds.contains(entry.cityId)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(MapTheme.rowTitleFont)
                    .foregroundStyle(MapTheme.primaryText)
                Text(detail(entry, isStored: isStored))
                    .font(MapTheme.rowDetailFont)
                    .foregroundStyle(MapTheme.tertiaryText)
            }
            Spacer(minLength: 8)
            Text(SpotProse.distance(metres: model.coordinate.distance(to: entry.center)))
                .font(MapTheme.rowDistanceFont)
                .foregroundStyle(MapTheme.secondaryText)
            if isStored {
                Button {
                    Task { await model.select(entry) }
                } label: {
                    Image(systemName: "map")
                        .foregroundStyle(MapTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(entry.name)")
            } else {
                Button {
                    Task { await model.download(entry) }
                } label: {
                    Text("Download for offline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MapTheme.background)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(MapTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isDownloading)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(MapTheme.sheet)
        .listRowSeparatorTint(MapTheme.rowRule)
        .swipeActions {
            if isStored {
                Button(role: .destructive) {
                    Task { await model.removeStoredCity(entry) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func detail(_ entry: CityIndexEntry, isStored: Bool) -> String {
        let size = MapViewModel.byteCount(entry.bytes)
        let state = isStored ? "on this device" : "not downloaded"
        return "\(entry.spotCount) spots · \(size) · \(state)"
    }
}

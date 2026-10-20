import MapKit
import SwiftUI

/// Add a stop by searching Apple Maps or by tapping the map.
struct AddStopView: View {
    @Environment(\.dismiss) private var dismiss
    let near: Coordinate?
    let onAdd: (Stop) -> Void

    @State private var search = PlaceSearch(kind: .places)
    @State private var query = ""
    @State private var position: MapCameraPosition = .automatic
    @State private var pin: Coordinate?
    @State private var pinName = ""
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $position) {
                        if let pin {
                            Marker(pinName.isEmpty ? String(localized: "New stop") : pinName, coordinate: pin.cl)
                                .tint(Color.accentColor)
                        }
                        UserAnnotation()
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        drop(at: Coordinate(coordinate))
                    }
                }
                .frame(height: 260)
                .overlay(alignment: .top) {
                    Text("Tap the map to drop a pin")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }

                List {
                    if let pin {
                        Section {
                            TextField("Name of the place", text: $pinName)
                            Button {
                                add(Stop(title: pinName.nilIfEmpty ?? String(localized: "New stop"), coordinate: pin))
                            } label: {
                                Label("Add this point", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                    Section {
                        ForEach(search.suggestions) { suggestion in
                            Button {
                                Task { await choose(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if isResolving { ProgressView() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Museum, café, street…"))
            .onChange(of: query) { _, text in search.update(query: text) }
            .navigationTitle("Add a stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let near {
                    search.setRegion(around: near)
                    position = .region(MKCoordinateRegion(center: near.cl, latitudinalMeters: 3000, longitudinalMeters: 3000))
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
        }
    }

    private func drop(at coordinate: Coordinate) {
        pin = coordinate
        pinName = ""
        Task {
            if let place = await PlaceSearch.town(at: coordinate), pin == coordinate, pinName.isEmpty {
                pinName = place.address ?? place.name
            }
        }
    }

    private func choose(_ suggestion: PlaceSearch.Suggestion) async {
        isResolving = true
        defer { isResolving = false }
        guard let place = await search.resolve(suggestion) else { return }
        add(Stop(title: place.name, coordinate: place.coordinate, category: place.category, address: place.address))
    }

    private func add(_ stop: Stop) {
        onAdd(stop)
        dismiss()
    }
}

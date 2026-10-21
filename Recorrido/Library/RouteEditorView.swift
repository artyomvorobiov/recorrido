import SwiftUI

/// Create or change a route: days, stops, order, transport, notes.
struct RouteEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Route
    let isNew: Bool

    @State private var addingToDay: DayRef?
    @State private var editingStop: StopRef?

    init(route: Route, isNew: Bool = false) {
        _draft = State(initialValue: route)
        self.isNew = isNew
    }

    struct DayRef: Identifiable {
        let id: String
    }

    struct StopRef: Identifiable {
        let dayID: String
        let stop: Stop
        var id: String { stop.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("About the route") {
                    HStack(spacing: 12) {
                        TextField("🧭", text: emojiBinding)
                            .font(.largeTitle)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                        VStack {
                            TextField("Title", text: $draft.title)
                                .font(.headline)
                            TextField("Town", text: $draft.city)
                        }
                    }
                    TextField("A few words about the route", text: $draft.summary, axis: .vertical)
                        .lineLimit(2...6)
                }

                ForEach($draft.days) { $day in
                    Section {
                        ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                            Button {
                                editingStop = StopRef(dayID: day.id, stop: stop)
                            } label: {
                                EditorStopRow(number: index + 1, stop: stop, isFirst: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                        .onMove { from, to in
                            day.stops.move(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { offsets in
                            day.stops.remove(atOffsets: offsets)
                        }

                        Button {
                            addingToDay = DayRef(id: day.id)
                        } label: {
                            Label("Add a stop", systemImage: "plus.circle.fill")
                        }

                        if day.stops.count > 2 {
                            Button {
                                withAnimation { day.stops = RoutePlanner.optimize(day.stops, keepFirst: true) }
                            } label: {
                                Label("Shortest order (keeps the first stop)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(for: day))
                            Spacer()
                            if draft.days.count > 1 {
                                Button(role: .destructive) {
                                    let id = day.id
                                    withAnimation { draft.days.removeAll { $0.id == id } }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Delete the day"))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        withAnimation { draft.days.append(RouteDay()) }
                    } label: {
                        Label("Add a day", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("Tip: in a small town put the stops you reach by car at the end of the day, and set “Car or taxi” for them.")
                }
            }
            .navigationTitle(isNew ? LocalizedStringKey("New route") : LocalizedStringKey("Edit route"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    EditButton()
                }
            }
            .sheet(item: $addingToDay) { ref in
                AddStopView(near: nearCoordinate) { stop in
                    append(stop, toDay: ref.id)
                }
            }
            .sheet(item: $editingStop) { ref in
                StopEditorView(stop: ref.stop) { updated in
                    replace(updated, inDay: ref.dayID)
                } onDelete: {
                    delete(ref.stop.id, inDay: ref.dayID)
                }
            }
        }
    }

    private var emojiBinding: Binding<String> {
        Binding(
            get: { draft.emoji },
            set: { value in
                if let last = value.last { draft.emoji = String(last) }
            }
        )
    }

    private var nearCoordinate: Coordinate? {
        draft.allStops.last?.coordinate ?? model.trip.location.location.map { Coordinate($0.coordinate) }
    }

    private func dayTitle(for day: RouteDay) -> String {
        let number = (draft.days.firstIndex { $0.id == day.id } ?? 0) + 1
        return String(localized: "Day \(number)")
    }

    private func append(_ stop: Stop, toDay dayID: String) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayID }) else { return }
        var stop = stop
        if let previous = draft.days[dayIndex].stops.last {
            let distance = Geo.distance(previous.coordinate, stop.coordinate)
            if distance > Pace.normal.comfortableWalkMeters {
                stop.arrival = Arrival(mode: .car)
            }
        }
        draft.days[dayIndex].stops.append(stop)
        if draft.city.isEmpty, let town = stop.address?.components(separatedBy: ",").first {
            draft.city = town.trimmingCharacters(in: .whitespaces)
        }
    }

    private func replace(_ stop: Stop, inDay dayID: String) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayID }),
              let stopIndex = draft.days[dayIndex].stops.firstIndex(where: { $0.id == stop.id }) else { return }
        draft.days[dayIndex].stops[stopIndex] = stop
    }

    private func delete(_ stopID: String, inDay dayID: String) {
        guard let dayIndex = draft.days.firstIndex(where: { $0.id == dayID }) else { return }
        draft.days[dayIndex].stops.removeAll { $0.id == stopID }
    }

    private func save() {
        var route = draft
        route.days.removeAll { $0.stops.isEmpty && draft.days.count > 1 }
        if route.days.isEmpty { route.days = [RouteDay()] }
        if route.source == .curated || route.source == .generated || route.source == .imported {
            // Editing makes it the user's own route.
            route.source = .user
        }
        model.library.upsert(route)
        dismiss()
    }
}

private struct EditorStopRow: View {
    let number: Int
    let stop: Stop
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 12) {
            StopBadge(number: number, tint: stop.category.tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.title).font(.body)
                HStack(spacing: 6) {
                    if !isFirst {
                        Image(systemName: stop.arrivalMode.symbol)
                            .foregroundStyle(stop.arrivalMode.tint)
                    }
                    Text(Format.duration(minutes: Double(stop.visitMinutes)))
                    if !stop.details.isEmpty {
                        Image(systemName: "text.alignleft")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

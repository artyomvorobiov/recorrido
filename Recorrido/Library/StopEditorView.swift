import SwiftUI

/// Edit one stop: name, story, tip, time, kind and how to get there.
struct StopEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stop: Stop
    private let onSave: (Stop) -> Void
    private let onDelete: () -> Void

    init(stop: Stop, onSave: @escaping (Stop) -> Void, onDelete: @escaping () -> Void) {
        _stop = State(initialValue: stop)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    TextField("Name", text: $stop.title)
                    Picker("Kind", selection: $stop.category) {
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    Stepper(value: $stop.visitMinutes, in: 0...480, step: 5) {
                        HStack {
                            Text("Time here")
                            Spacer()
                            Text(Format.duration(minutes: Double(stop.visitMinutes)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Story") {
                    TextField("What is interesting here", text: $stop.details, axis: .vertical)
                        .lineLimit(3...12)
                    TextField("Local tip", text: tipBinding, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Picker("Getting here", selection: modeBinding) {
                        ForEach(TransportMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    TextField("How exactly, e.g. “tram 3 to the Kremlin”", text: noteBinding, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Getting here")
                } footer: {
                    Text("From the previous stop. For the first stop of a day this is ignored.")
                }

                Section {
                    Button("Delete the stop", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(stop.title.isEmpty ? String(localized: "Stop") : stop.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(stop)
                        dismiss()
                    }
                    .disabled(stop.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var tipBinding: Binding<String> {
        Binding(
            get: { stop.tip ?? "" },
            set: { stop.tip = $0.nilIfEmpty }
        )
    }

    private var modeBinding: Binding<TransportMode> {
        Binding(
            get: { stop.arrivalMode },
            set: { mode in
                stop.arrival = Arrival(mode: mode, note: stop.arrival?.note)
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { stop.arrival?.note ?? "" },
            set: { note in
                stop.arrival = Arrival(mode: stop.arrivalMode, note: note.nilIfEmpty)
            }
        )
    }
}

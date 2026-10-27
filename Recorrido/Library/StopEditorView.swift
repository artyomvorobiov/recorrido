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
                    TextField("In a few words: what is this place", text: $stop.details, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Local tip", text: tipBinding, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    TextField("Tell it like a guide: history, people, what you love here", text: storyBinding, axis: .vertical)
                        .lineLimit(4...20)
                    TextField("What to find with your own eyes — one per line", text: lookForBinding, axis: .vertical)
                        .lineLimit(2...8)
                } header: {
                    Text("Guide")
                } footer: {
                    Text("Your story travels with the route when you share it or publish it in the feed. Separate paragraphs with an empty line.")
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

    private var storyBinding: Binding<String> {
        Binding(
            get: { stop.guide?.story ?? "" },
            set: { story in
                var guide = takeOwnGuide()
                guide.story = story
                stop.guide = guide.isEmpty ? nil : guide
            }
        )
    }

    private var lookForBinding: Binding<String> {
        Binding(
            get: { stop.guide?.lookFor.joined(separator: "\n") ?? "" },
            set: { text in
                var guide = takeOwnGuide()
                guide.lookFor = text.components(separatedBy: "\n").compactMap(\.nilIfEmpty)
                stop.guide = guide.isEmpty ? nil : guide
            }
        )
    }

    /// The guide the user is editing. Once rewritten, a catalog stop's guide
    /// is the user's own and is no longer replaced by the catalog text.
    private func takeOwnGuide() -> StopGuide {
        if stop.ref != nil { stop.ref = nil }
        return stop.guide ?? StopGuide()
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

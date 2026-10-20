import SwiftUI

/// Builds a route for any town from a few choices.
struct GeneratorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let launch: GeneratorLaunch
    @State private var generator = GeneratorModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Any town")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if case .done(let route) = generator.phase {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                dismiss()
                                model.saveImported(route)
                            }
                        }
                    }
                }
        }
        .onAppear { generator.prefill(launch) }
    }

    @ViewBuilder
    private var content: some View {
        switch generator.phase {
        case .form:
            form
        case .working(let stage):
            WorkingView(stage: stage)
        case .done(let route):
            RouteDetailView(route: route, mode: .preview)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        generator.phase = .form
                    } label: {
                        Label("Change options", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
        case .failed(let message):
            VStack(spacing: 16) {
                ContentUnavailableView("Nothing yet", systemImage: "map", description: Text(message))
                Button("Try again") { generator.phase = .form }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var form: some View {
        @Bindable var generator = generator
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Where")
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Town, e.g. Pereslavl-Zalessky", text: $generator.townQuery)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onChange(of: generator.townQuery) { _, _ in generator.queryChanged() }
                        if generator.town != nil {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .card(padding: 14)

                    if searchFocused || generator.town == nil {
                        ForEach(generator.search.suggestions) { suggestion in
                            Button {
                                searchFocused = false
                                Task { await generator.choose(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).font(.body)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        searchFocused = false
                        Task { await generator.useCurrentLocation(model.trip.location) }
                    } label: {
                        HStack {
                            Label("I'm in this town now", systemImage: "location.fill")
                            if generator.isLocating { ProgressView().padding(.leading, 4) }
                        }
                    }
                    .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("How much time")
                    FlowLayout {
                        ForEach(GeneratorModel.LengthChoice.allCases, id: \.self) { choice in
                            Chip(title: choice.title, isSelected: generator.length == choice) {
                                generator.length = choice
                            }
                        }
                    }
                    if generator.length == .auto {
                        Text("Small town — a walk for a few hours or a day; big city — two or three days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Getting around")
                    VStack(spacing: 8) {
                        ForEach(Mobility.allCases, id: \.self) { option in
                            Chip(title: option.title, symbol: option.symbol, isSelected: generator.mobility == option) {
                                generator.mobility = option
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("Sights a few kilometres out of town get a car or taxi leg — handy for monasteries and estates nearby.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Pace")
                    Picker("Pace", selection: $generator.pace) {
                        ForEach(Pace.allCases, id: \.self) { pace in
                            Text(pace.title).tag(pace)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Interesting to me")
                    FlowLayout {
                        ForEach(GeneratorModel.Interest.allCases, id: \.self) { interest in
                            Chip(title: interest.title, symbol: interest.symbol, isSelected: generator.interests.contains(interest)) {
                                if generator.interests.contains(interest) {
                                    generator.interests.remove(interest)
                                } else {
                                    generator.interests.insert(interest)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Start from where I am", isOn: $generator.startFromHere)
                    if generator.startFromHere {
                        Toggle("Come back to the start", isOn: $generator.returnToStart)
                    }
                }
                .card()

                Button {
                    searchFocused = false
                    Task { await generator.generate(location: model.trip.location) }
                } label: {
                    Label("Build the route", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!generator.canGenerate)

                Text("Places and descriptions come from Wikipedia, paths from Apple Maps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.headline)
    }
}

/// Progress while the route is being built.
private struct WorkingView: View {
    let stage: GeneratorStage

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            VStack(alignment: .leading, spacing: 10) {
                step("Looking for interesting places", done: stage != .searching, active: stage == .searching)
                step("Choosing the best and planning the way", done: stage == .describing, active: stage == .selecting)
                step("Writing the guide", done: false, active: stage == .describing)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ title: LocalizedStringKey, done: Bool, active: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.dotted" : "circle")
                .foregroundStyle(done ? Color.green : active ? Color.accentColor : Color.secondary)
        }
        .font(.subheadline.weight(active ? .semibold : .regular))
    }
}

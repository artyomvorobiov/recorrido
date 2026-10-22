import SwiftUI

struct RouteDetailView: View {
    enum Mode {
        /// A route from the catalog or the library.
        case standard
        /// Not saved yet: a received or freshly generated route.
        case preview
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let route: Route
    var mode: Mode = .standard

    @State private var dayIndex = 0
    @State private var directions = RouteDirections()
    @State private var selectedStop: Stop?
    @State private var showsShare = false
    @State private var showsMap = false
    @State private var editing: Route?
    @State private var confirmsDelete = false
    @State private var confirmsReplaceTrip = false
    @State private var startTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()

    private var current: Route {
        mode == .standard ? model.latest(route) : route
    }

    private var day: RouteDay {
        current.days[safe: dayIndex] ?? current.days.first ?? RouteDay()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mapPreview
                header
                actions
                if current.days.count > 1 {
                    dayPicker
                }
                RouteTimeline(
                    route: current,
                    day: day,
                    directions: directions,
                    startTime: $startTime,
                    onSelect: { selectedStop = $0 }
                )
                footer
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $selectedStop) { stop in
            StopDetailView(stop: stop, route: current)
        }
        .sheet(isPresented: $showsShare) {
            ShareRouteView(route: current, dayIndex: dayIndex, directions: directions)
        }
        .sheet(item: $editing) { route in
            RouteEditorView(route: route)
        }
        .fullScreenCover(isPresented: $showsMap) {
            FullRouteMap(title: current.title, stops: day.stops, directions: directions) { stop in
                selectedStop = stop
            }
        }
        .confirmationDialog("Delete this route?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.library.delete(routeID: current.id)
                dismiss()
            }
        }
        .confirmationDialog("Another walk is in progress", isPresented: $confirmsReplaceTrip, titleVisibility: .visible) {
            Button("Start this route instead") { startWalk() }
        } message: {
            Text("The current walk will be finished.")
        }
        .task(id: LoadKey(routeID: current.id, day: dayIndex, version: current.updatedAt)) {
            await model.media.prefetch(day.stops)
            await directions.load(day.stops, using: model.directions)
        }
        .onChange(of: current.days.count) { _, count in
            if dayIndex >= count { dayIndex = 0 }
        }
    }

    private struct LoadKey: Equatable {
        let routeID: String
        let day: Int
        let version: Date
    }

    // MARK: - Sections

    private var mapPreview: some View {
        RouteMapView(stops: day.stops, directions: directions, interactive: false)
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .padding(9)
                    .background(.thinMaterial, in: Circle())
                    .padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture { showsMap = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Open the map"))
            .padding(.top, 8)
    }

    private var header: some View {
        let estimate = RouteEstimator.route(current)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                EmojiTile(emoji: current.emoji, seed: current.id, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text([current.city, current.country].compactMap { $0?.nilIfEmpty }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !current.summary.isEmpty {
                Text(current.summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let intro = current.intro {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "signpost.right.and.left")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before you set off")
                            .font(.subheadline.weight(.semibold))
                        Text(intro)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
            HStack(spacing: 12) {
                StatBlock(value: current.lengthLabel, caption: String(localized: "time"), symbol: "clock")
                StatBlock(value: Format.distance(estimate.distance), caption: String(localized: "distance"), symbol: "point.topleft.down.to.point.bottomright.curvepath")
                StatBlock(value: "\(current.stopCount)", caption: String(localized: "stops"), symbol: "mappin.and.ellipse")
            }
            .card(padding: 12)
            if current.modes.contains(where: { $0 != .walk }) {
                HStack(spacing: 8) {
                    ForEach(current.modes, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(mode.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(mode.tint)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                if let active = model.trip.active, active.routeID != current.id {
                    confirmsReplaceTrip = true
                } else if model.trip.isActive(current), model.trip.active?.dayIndex == dayIndex {
                    model.trip.isPresented = true
                } else {
                    startWalk()
                }
            } label: {
                Label(model.trip.isActive(current) ? LocalizedStringKey("Continue") : LocalizedStringKey("Start"),
                      systemImage: "figure.walk")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.toggleSaved(current)
            } label: {
                Image(systemName: model.isSaved(current) ? "bookmark.fill" : "bookmark")
                    .frame(width: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(model.isSaved(current) ? Text("Remove from My routes") : Text("Save to My routes"))

            Button {
                showsShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(Text("Share"))
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Day", selection: $dayIndex) {
                ForEach(current.days.indices, id: \.self) { index in
                    Text("Day \(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            if let title = day.title {
                Text(title).font(.headline)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if current.hasWikipediaContent {
                Text("Photos: Wikipedia / Wikimedia Commons (CC BY-SA). Generated stories: Wikipedia.")
            }
            if let author = current.author, current.source != .curated {
                Text("Author: \(author)")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if model.isInLibrary(current) {
                    Button {
                        editing = current
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                } else if mode == .standard {
                    Button {
                        editing = model.makeEditableCopy(of: current)
                    } label: {
                        Label("Make my own version", systemImage: "square.on.square")
                    }
                }
                if let url = current.googleMapsURL(day: dayIndex) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in Google Maps", systemImage: "map")
                    }
                }
                if let first = day.stops.first {
                    Button {
                        first.openDirections(mode: .walk)
                    } label: {
                        Label("Directions to the start", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                }
                if model.isInLibrary(current) {
                    Divider()
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func startWalk() {
        model.trip.start(current, day: dayIndex)
    }
}

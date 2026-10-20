import AppIntents
import SwiftUI
import WidgetKit

/// Home and lock screen widget: the next stop of the walk (with an
/// "I'm here" button), or the route of the day when no walk is running.
struct TripWidget: Widget {
    let kind = "TripWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripProvider()) { entry in
            TripWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("WidgetBackground")
                }
        }
        .configurationDisplayName("Recorrido")
        .description("Your walk: the next stop and progress. Without a walk — a route of the day.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct TripEntry: TimelineEntry {
    let date: Date
    let trip: ActiveTrip?
    let featured: Route?
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: Date(), trip: nil, featured: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let entry = makeEntry()
        // The app reloads the widget on every check-in; the schedule only
        // refreshes the route of the day after midnight.
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60))
        let next = entry.trip == nil ? tomorrow : min(tomorrow, Date().addingTimeInterval(60 * 60))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> TripEntry {
        let trip = AppGroup.storage.trip.readSafely()
        let featured = trip == nil ? CatalogLoader.load().routeOfTheDay(for: Date()) : nil
        return TripEntry(date: Date(), trip: trip, featured: featured)
    }
}

struct TripWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TripEntry

    var body: some View {
        Group {
            if let trip = entry.trip {
                tripView(trip)
            } else {
                featuredView(entry.featured)
            }
        }
        .widgetURL(url)
    }

    private var url: URL? {
        if entry.trip != nil { return URL(string: "recorrido://trip") }
        if let route = entry.featured { return URL(string: "recorrido://route/\(route.id)") }
        return URL(string: "recorrido://")
    }

    // MARK: - Walk in progress

    @ViewBuilder
    private func tripView(_ trip: ActiveTrip) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: trip.progress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(verbatim: "\(min(trip.currentIndex, trip.stops.count))/\(trip.stops.count)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(trip.isFinished ? LocalizedStringKey("Route completed") : LocalizedStringKey("Next stop"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(trip.nextStop?.title ?? trip.routeTitle)
                    .font(.headline)
                    .lineLimit(2)
                ProgressView(value: trip.progress)
            }
        case .accessoryInline:
            if let next = trip.nextStop {
                Label(next.title, systemImage: next.mode.symbol)
            } else {
                Label(trip.routeTitle, systemImage: "flag.checkered")
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header(trip)
                Spacer(minLength: 0)
                nextStopText(trip)
                ProgressView(value: trip.progress).tint(Color.accentColor)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                header(trip)
                Text(trip.routeTitle).font(.headline).lineLimit(1)
                ForEach(Array(trip.stops.prefix(8).enumerated()), id: \.element.id) { index, stop in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: index, in: trip))
                            .foregroundStyle(index == trip.currentIndex ? Color.accentColor : Color.secondary)
                        Text(stop.title)
                            .font(.subheadline.weight(index == trip.currentIndex ? .semibold : .regular))
                            .foregroundStyle(index < trip.currentIndex ? Color.secondary : Color.primary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                checkInButton(trip)
            }
        default:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    header(trip)
                    Spacer(minLength: 0)
                    nextStopText(trip)
                    ProgressView(value: trip.progress).tint(Color.accentColor)
                }
                if !trip.isFinished {
                    checkInButton(trip)
                        .frame(width: 92)
                }
            }
        }
    }

    private func header(_ trip: ActiveTrip) -> some View {
        HStack(spacing: 6) {
            Text(trip.emoji)
            Text(verbatim: "\(min(trip.currentIndex + 1, trip.stops.count))/\(trip.stops.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func nextStopText(_ trip: ActiveTrip) -> some View {
        if let next = trip.nextStop {
            VStack(alignment: .leading, spacing: 2) {
                Label(next.mode.title, systemImage: next.mode.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(next.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text("Route completed").font(.headline)
        }
    }

    private func checkInButton(_ trip: ActiveTrip) -> some View {
        Button(intent: CheckInIntent()) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
                Text("I'm here")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Color.accentColor)
        .disabled(trip.isFinished)
    }

    private func icon(for index: Int, in trip: ActiveTrip) -> String {
        if trip.visitedIDs.contains(trip.stops[index].id) { return "checkmark.circle.fill" }
        if index == trip.currentIndex { return "location.circle.fill" }
        return "circle"
    }

    // MARK: - Route of the day

    @ViewBuilder
    private func featuredView(_ route: Route?) -> some View {
        if let route {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Text(route.emoji).font(.title2)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Route of the day").font(.caption2).foregroundStyle(.secondary)
                    Text(route.title).font(.headline).lineLimit(2)
                }
            case .accessoryInline:
                Text(route.title)
            case .systemSmall:
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.emoji).font(.largeTitle)
                    Spacer(minLength: 0)
                    Text("Route of the day").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Text(route.title).font(.headline).lineLimit(3).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(route.emoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Route of the day").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            Text(route.title).font(.headline).lineLimit(2)
                            Text(route.city).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if family == .systemLarge {
                        Text(route.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        ForEach(Array((route.days.first?.stops ?? []).prefix(6).enumerated()), id: \.element.id) { index, stop in
                            HStack(spacing: 8) {
                                Text(verbatim: "\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(stop.category.tint))
                                Text(stop.title).font(.subheadline).lineLimit(1)
                            }
                        }
                    } else {
                        Text(route.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        Label(route.lengthText, systemImage: "clock")
                        Label("\(route.stopCount)", systemImage: "mappin.and.ellipse")
                        Spacer()
                        ModeIconsSmall(modes: route.modes)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "🧭").font(.largeTitle)
                Text("Small towns, big walks").font(.headline)
            }
        }
    }
}

private struct ModeIconsSmall: View {
    let modes: [TransportMode]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(modes.prefix(3), id: \.self) { mode in
                Image(systemName: mode.symbol)
            }
        }
    }
}

private extension Route {
    var lengthText: String {
        if days.count > 1 { return String(localized: "\(days.count) days") }
        return Format.duration(minutes: RouteEstimator.route(self).totalMinutes)
    }
}

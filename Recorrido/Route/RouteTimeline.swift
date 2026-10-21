import SwiftUI

/// The day as a schedule: stops with arrival times and the ways between them.
struct RouteTimeline: View {
    @Environment(AppModel.self) private var model
    let route: Route
    let day: RouteDay
    let directions: RouteDirections
    @Binding var startTime: Date
    let onSelect: (Stop) -> Void

    var body: some View {
        let legs = directions.geometry(for: day.stops)
        let times = schedule(legs: legs)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Plan of the day").font(.title3.bold())
                Spacer()
                Text("Start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.bottom, 12)

            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0, legs.indices.contains(index - 1) {
                    LegRow(stop: stop, leg: legs[index - 1])
                }
                Button {
                    onSelect(stop)
                } label: {
                    StopRow(number: index + 1, stop: stop, arrival: times[safe: index],
                            imageURL: model.media.imageURL(for: stop))
                }
                .buttonStyle(.plain)
            }

            if let lastTime = times.last, let lastStop = day.stops.last {
                let finish = lastTime.addingTimeInterval(Double(lastStop.visitMinutes) * 60)
                Label("Finish around \(Format.time(finish))", systemImage: "flag.checkered")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            }

            if day.stops.isEmpty {
                Text("No stops yet.")
                    .foregroundStyle(.secondary)
                    .card()
            }
        }
    }

    private func schedule(legs: [LegGeometry]) -> [Date] {
        var result: [Date] = []
        var clock = startTime
        for (index, stop) in day.stops.enumerated() {
            if index > 0, legs.indices.contains(index - 1) {
                clock = clock.addingTimeInterval(legs[index - 1].seconds)
            }
            result.append(clock)
            clock = clock.addingTimeInterval(Double(stop.visitMinutes) * 60)
        }
        return result
    }
}

struct StopRow: View {
    let number: Int
    let stop: Stop
    var arrival: Date?
    var imageURL: URL?
    var isDone = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StopBadge(number: number, tint: stop.category.tint, isDone: isDone)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let arrival {
                        Text(Format.time(arrival)).monospacedDigit()
                    }
                    if stop.visitMinutes > 0 {
                        Text(verbatim: "· \(Format.duration(minutes: Double(stop.visitMinutes)))")
                    }
                    Image(systemName: stop.category.symbol)
                        .foregroundStyle(stop.category.tint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(stop.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                if !stop.details.isEmpty {
                    Text(stop.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                if let tip = stop.tip {
                    Label(tip, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if let imageURL {
                RemotePhoto(url: imageURL)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
        .contentShape(Rectangle())
    }
}

/// How to get to `stop` from the previous one.
struct LegRow: View {
    let stop: Stop
    let leg: LegGeometry

    var body: some View {
        let mode = stop.arrivalMode
        HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(mode.tint.opacity(0.5))
                .frame(width: 3, height: 38)
                .padding(.leading, 26)
            Image(systemName: mode.symbol)
                .foregroundStyle(mode.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(Format.duration(minutes: leg.minutes)) · \(Format.distance(leg.distance))")
                    .monospacedDigit()
                if let note = stop.arrival?.note {
                    Text(note).lineLimit(2)
                } else if mode != .walk {
                    Text(mode.title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

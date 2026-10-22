import MapKit
import SwiftUI

/// The walk itself: the map follows you, the card says where to go next,
/// the audio guide tells the story when you arrive.
struct TripView: View {
    @Environment(AppModel.self) private var model
    @State private var directions = RouteDirections()
    @State private var selectedStop: Stop?
    @State private var confirmsEnd = false

    private var trip: TripController { model.trip }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let day = trip.currentDay, let active = trip.active {
                RouteMapView(
                    stops: day.stops,
                    directions: directions,
                    interactive: true,
                    showsUser: true,
                    visited: Set(active.visitedIDs),
                    highlighted: active.nextStop?.id
                ) { stop in
                    selectedStop = stop
                }
                .ignoresSafeArea()
            } else {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            }

            card
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .top) { topBar }
        .sensoryFeedback(.success, trigger: trip.arrivedStopID)
        .sensoryFeedback(.impact, trigger: trip.active?.currentIndex)
        .sheet(item: $selectedStop) { stop in
            if let route = trip.route {
                StopDetailView(stop: stop, route: route)
            }
        }
        .confirmationDialog("Finish the walk?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("Finish", role: .destructive) { trip.end() }
        } message: {
            Text("Visited places stay in your passport.")
        }
        .task(id: trip.currentDay?.id) {
            if let day = trip.currentDay {
                await model.media.prefetch(day.stops)
                await directions.load(day.stops, using: model.directions)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                trip.isPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text("Minimize"))

            VStack(alignment: .leading, spacing: 1) {
                Text(trip.active?.routeTitle ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let active = trip.active, active.dayCount > 1 {
                    Text("Day \(active.dayIndex + 1) of \(active.dayCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())

            Spacer()

            Menu {
                if let active = trip.active, !active.stops.isEmpty {
                    Section("Go to a stop") {
                        ForEach(Array(active.stops.enumerated()), id: \.element.id) { index, stop in
                            Button {
                                trip.goTo(stopID: stop.id)
                            } label: {
                                Text(verbatim: "\(index + 1). \(stop.title)")
                            }
                        }
                    }
                }
                Button(role: .destructive) {
                    confirmsEnd = true
                } label: {
                    Label("Finish the walk", systemImage: "flag.checkered")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var card: some View {
        if let active = trip.active {
            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: active.progress)
                    .tint(Color.accentColor)
                if active.isFinished {
                    finished(active)
                } else if let next = active.nextStop {
                    nextStop(next, active: active)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    private func nextStop(_ next: TripStop, active: ActiveTrip) -> some View {
        let isHere = trip.arrivedStopID == next.id
        let full = trip.nextStop
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StopBadge(number: active.currentIndex + 1, tint: next.category.tint, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isHere ? LocalizedStringKey("You're here") : LocalizedStringKey("Next stop"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isHere ? Color.green : Color.secondary)
                    Text(next.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                    if !isHere {
                        distanceLine(next)
                    }
                }
                Spacer(minLength: 0)
                if !isHere, let bearing = trip.bearingToNext {
                    Image(systemName: "location.north.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(bearing - (trip.location.heading ?? 0)))
                        .animation(.easeOut(duration: 0.3), value: bearing - (trip.location.heading ?? 0))
                        .accessibilityHidden(true)
                }
            }

            if isHere, let full {
                let opening = full.guide?.paragraphs.first ?? full.details
                if !opening.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(opening)
                            .font(.subheadline)
                            .lineLimit(4)
                        if full.guide != nil {
                            Text("Tap for the whole story, things to find and a question")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedStop = full }
                }
            } else if let approach = full?.guide?.approach {
                Text(approach)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .onTapGesture { selectedStop = full }
            }

            HStack(spacing: 10) {
                Button {
                    trip.checkIn()
                } label: {
                    Label("I'm here", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let full {
                    Button {
                        trip.audio.toggle(id: full.id, text: AudioGuide.script(for: full), language: trip.route?.language)
                    } label: {
                        Image(systemName: trip.audio.isSpeaking(full.id) ? "pause.fill" : "headphones")
                            .frame(width: 28)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Listen"))

                    Button {
                        full.openDirections(mode: next.mode)
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .frame(width: 28)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Directions"))

                    Button {
                        selectedStop = full
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 28)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("About this place"))
                }
            }
            .controlSize(.large)

            HStack {
                Button("Back") { trip.stepBack() }
                    .disabled(active.currentIndex == 0)
                Spacer()
                Text("\(active.currentIndex + 1) of \(active.stops.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { trip.skip() }
            }
            .font(.subheadline)
        }
    }

    private func distanceLine(_ next: TripStop) -> some View {
        HStack(spacing: 6) {
            Image(systemName: next.mode.symbol)
                .foregroundStyle(next.mode.tint)
            if let distance = trip.distanceToNext {
                let minutes = distance * next.mode.detourFactor / 1000 / next.mode.speedKmh * 60
                Text(verbatim: "\(Format.distance(distance)) · \(Format.duration(minutes: minutes))")
            } else if trip.location.isDenied {
                Text("Location is off — check in by hand")
            } else {
                Text(next.mode.title)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func finished(_ active: ActiveTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route completed!")
                .font(.title2.bold())
            Text("\(active.visitedCount) places visited. They are stamped in your passport.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if trip.hasNextDay {
                    Button {
                        trip.startNextDay()
                    } label: {
                        Label("Day \(active.dayIndex + 2)", systemImage: "sunrise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    trip.end()
                } label: {
                    Text("Finish")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
}

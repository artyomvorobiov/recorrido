import SwiftUI

/// The traveller's passport: stamps for every town and the numbers behind them.
struct PassportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        StatBlock(value: "\(library.placesVisited)", caption: String(localized: "places"), symbol: "mappin.and.ellipse")
                        StatBlock(value: "\(library.stamps.count)", caption: String(localized: "towns"), symbol: "building.2")
                        StatBlock(value: Format.distance(library.walkedMeters), caption: String(localized: "on foot"), symbol: "figure.walk")
                        StatBlock(value: "\(library.data.completed.count)", caption: String(localized: "routes"), symbol: "flag.checkered")
                    }
                    .card(padding: 14)

                    let score = model.quizScore
                    if score.answered > 0 || library.progress.foundCount > 0 {
                        HStack(spacing: 12) {
                            StatBlock(value: "\(library.progress.foundCount)", caption: String(localized: "details found"), symbol: "eye")
                            StatBlock(value: "\(score.right)/\(score.answered)", caption: String(localized: "questions right"), symbol: "questionmark.bubble")
                        }
                        .card(padding: 14)
                    }

                    if library.stamps.isEmpty {
                        ContentUnavailableView {
                            Label("No stamps yet", systemImage: "seal")
                        } description: {
                            Text("Start a route and tap “I'm here” at each stop — every town you walk gets a stamp.")
                        }
                        .padding(.top, 24)
                    } else {
                        Text("Stamps").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 14) {
                            ForEach(library.stamps) { stamp in
                                StampView(stamp: stamp, emoji: emoji(for: stamp.town))
                            }
                        }

                        Text("Recently visited").font(.title3.bold())
                        VStack(spacing: 0) {
                            ForEach(library.visits.suffix(12).reversed()) { visit in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(visit.title).font(.body)
                                        Text(visit.city).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.day(visit.date)).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                        .card(padding: 14)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Passport")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
        }
    }

    private func emoji(for town: String) -> String {
        model.catalog.cities.first { $0.name == town }?.emoji ?? "📍"
    }
}

/// A round ink stamp, slightly tilted like a real one.
struct StampView: View {
    let stamp: LibraryStore.TownStamp
    let emoji: String

    /// The same small tilt for the same town on every launch.
    private var tilt: Double {
        let seed = stamp.town.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(seed % 13) - 6
    }

    var body: some View {
        let tint = Color.tile(for: stamp.town)
        VStack(spacing: 4) {
            Text(emoji).font(.title)
            Text(stamp.town)
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            Text(Format.day(stamp.firstVisit))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(tint.opacity(0.95))
        .padding(10)
        .frame(width: 104, height: 104)
        .background(
            Circle()
                .strokeBorder(tint, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                .background(Circle().fill(tint.opacity(0.08)))
        )
        .overlay(alignment: .topTrailing) {
            Text("\(stamp.places)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(tint))
        }
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .combine)
    }
}

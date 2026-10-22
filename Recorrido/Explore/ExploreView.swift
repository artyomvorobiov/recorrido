import SwiftUI

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.explorePath) {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    content
                } else {
                    SearchResults(query: query)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Recorrido")
            .searchable(text: $query, prompt: Text("Town, route or place"))
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .navigationDestination(for: City.self) { city in
                CityView(city: city)
            }
            .navigationDestination(for: CommunityRoute.self) { item in
                CommunityRouteScreen(item: item)
            }
        }
    }

    private var smallTowns: [City] {
        model.catalog.cities.filter { $0.size != .large }
    }

    private var bigCities: [City] {
        model.catalog.cities.filter { $0.size == .large }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            if model.trip.active != nil {
                ContinueTripCard()
            }

            GeneratorCard()

            if !smallTowns.isEmpty {
                section(
                    title: "Small towns",
                    subtitle: "A day on foot — with a short drive to the sights nearby"
                ) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(smallTowns) { city in
                            NavigationLink(value: city) {
                                CityCard(city: city)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let route = model.catalog.routeOfTheDay(for: Date()) {
                section(title: "Route of the day", subtitle: nil) {
                    NavigationLink(value: route) {
                        RouteCard(route: route)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !bigCities.isEmpty {
                section(title: "Big cities", subtitle: "Two or three days, one area a day") {
                    VStack(spacing: 12) {
                        ForEach(bigCities) { city in
                            ForEach(model.catalog.routes(inCity: city.id)) { route in
                                NavigationLink(value: route) {
                                    RouteCard(route: route)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Text("Texts are written for Recorrido; photos come from Wikipedia. Opening hours change — check them before you go.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func section<Content: View>(title: LocalizedStringKey, subtitle: LocalizedStringKey?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }
}

/// Catalog matches plus "build a route for this town".
private struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let query: String

    var body: some View {
        let result = model.catalog.search(query)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.cities) { city in
                NavigationLink(value: city) {
                    CityRow(city: city)
                }
                .buttonStyle(.plain)
            }
            ForEach(result.routes) { route in
                NavigationLink(value: route) {
                    RouteCard(route: route)
                }
                .buttonStyle(.plain)
            }
            Button {
                model.generatorLaunch = GeneratorLaunch(townName: query)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build a route for “\(query)”").font(.headline)
                        Text("From the most interesting places nearby, in a few seconds")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card()
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct GeneratorCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.generatorLaunch = GeneratorLaunch()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Any town")
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                Text("A route for any town in seconds")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Pick a town and how much time you have — Recorrido finds the sights, puts them in order and works out where you'll need a car.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ContinueTripCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let trip = model.trip.active {
            Button {
                model.trip.isPresented = true
            } label: {
                HStack(spacing: 14) {
                    EmojiTile(emoji: trip.emoji, seed: trip.routeID, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Continue the walk").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        Text(trip.routeTitle).font(.headline).lineLimit(1)
                        if let next = trip.nextStop {
                            Text("Next: \(next.title)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text("All stops visited").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

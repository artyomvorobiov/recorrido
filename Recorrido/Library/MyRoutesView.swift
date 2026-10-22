import SwiftUI

struct MyRoutesView: View {
    @Environment(AppModel.self) private var model
    @State private var newRoute: Route?

    var body: some View {
        @Bindable var model = model
        let own = model.library.routes
        let saved = model.savedCatalogRoutes()
        NavigationStack(path: $model.libraryPath) {
            List {
                if model.trip.active != nil {
                    Section {
                        ContinueTripCard()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if !own.isEmpty {
                    Section("Created and received") {
                        ForEach(own) { route in
                            NavigationLink(value: route) {
                                RouteListRow(route: route)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.library.delete(routeID: own[index].id)
                            }
                        }
                    }
                }
                if !saved.isEmpty {
                    Section("Saved from the catalog") {
                        ForEach(saved) { route in
                            NavigationLink(value: route) {
                                RouteListRow(route: route)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.library.toggleSaved(saved[index].id)
                            }
                        }
                    }
                }
            }
            .overlay {
                if own.isEmpty && saved.isEmpty {
                    ContentUnavailableView {
                        Label("No routes yet", systemImage: "bookmark")
                    } description: {
                        Text("Save routes from the catalog, build one for any town, or make your own — and share it with friends.")
                    } actions: {
                        Button("Build a route for a town") {
                            model.generatorLaunch = GeneratorLaunch()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Create from scratch") {
                            newRoute = blankRoute()
                        }
                    }
                }
            }
            .navigationTitle("My routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            model.generatorLaunch = GeneratorLaunch()
                        } label: {
                            Label("Build for any town", systemImage: "wand.and.stars")
                        }
                        Button {
                            newRoute = blankRoute()
                        } label: {
                            Label("Create from scratch", systemImage: "pencil.and.list.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .navigationDestination(for: City.self) { city in
                CityView(city: city)
            }
            .navigationDestination(for: CommunityRoute.self) { item in
                CommunityRouteScreen(item: item)
            }
            .sheet(item: $newRoute) { route in
                RouteEditorView(route: route, isNew: true)
            }
        }
    }

    private func blankRoute() -> Route {
        Route(title: String(localized: "My route"), city: "", emoji: "🧭", source: .user, author: nil, days: [RouteDay()])
    }
}

struct RouteListRow: View {
    @Environment(AppModel.self) private var model
    let route: Route

    private var isPublished: Bool {
        model.library.publication(for: route.id) != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            EmojiTile(emoji: route.emoji, seed: route.id, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(route.title).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    if !route.city.isEmpty {
                        Text(route.city)
                    }
                    Text(verbatim: "·")
                    Text("\(route.stopCount) stops")
                    if route.source == .imported {
                        Image(systemName: "arrow.down.circle")
                    } else if route.source == .generated {
                        Image(systemName: "wand.and.stars")
                    }
                    if isPublished {
                        Image(systemName: "checkmark.icloud")
                            .accessibilityLabel(Text("In the feed"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

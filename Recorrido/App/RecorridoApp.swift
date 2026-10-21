import SwiftUI

@main
struct RecorridoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SettingsKey.registerDefaults()
        // Photos from Wikipedia stay available offline once seen.
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.didBecomeActive() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var trip = model.trip
        TabView(selection: $model.tab) {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "map") }
                .tag(AppTab.explore)
            MyRoutesView()
                .tabItem { Label("My routes", systemImage: "bookmark") }
                .tag(AppTab.library)
            PassportView()
                .tabItem { Label("Passport", systemImage: "seal") }
                .tag(AppTab.passport)
        }
        .fullScreenCover(isPresented: $trip.isPresented) {
            TripView()
        }
        .sheet(item: $model.importRequest) { request in
            ImportRouteView(route: request.route)
        }
        .sheet(item: $model.generatorLaunch) { launch in
            GeneratorView(launch: launch)
        }
        .alert("Recorrido", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

import CloudKit
import SwiftUI

/// Routes other travellers published: the newest, the nearest, or by town.
struct CommunityView: View {
    @Environment(AppModel.self) private var model

    enum Feed: Hashable {
        case latest, nearby
    }

    @State private var feed: Feed = .latest
    @State private var query = ""
    @State private var routes: [CommunityRoute] = []
    @State private var isLoading = false
    @State private var problem: String?
    @State private var choosesRoute = false
    @State private var publishing: Route?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Feed", selection: $feed) {
                        Text("New").tag(Feed.latest)
                        Text("Nearby").tag(Feed.nearby)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!query.isEmpty)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                ForEach(visible) { item in
                    NavigationLink(value: item) {
                        CommunityRow(item: item)
                    }
                }
            }
            .overlay { overlay }
            .navigationTitle("Travellers")
            .searchable(text: $query, prompt: Text("Town"))
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: query) { _, text in
                if text.isEmpty { Task { await load() } }
            }
            .refreshable { await load() }
            .task(id: feed) { await load() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        choosesRoute = true
                    } label: {
                        Label("Publish a route", systemImage: "plus.circle")
                    }
                }
            }
            .navigationDestination(for: CommunityRoute.self) { item in
                CommunityRouteScreen(item: item)
            }
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .sheet(isPresented: $choosesRoute) {
                PublishPicker { route in
                    choosesRoute = false
                    publishing = route
                }
            }
            .sheet(item: $publishing) { route in
                PublishRouteView(route: route)
            }
        }
    }

    private var visible: [CommunityRoute] {
        model.visibleCommunityRoutes(routes)
    }

    @ViewBuilder
    private var overlay: some View {
        if isLoading && routes.isEmpty {
            ProgressView()
        } else if let problem {
            ContentUnavailableView {
                Label("The feed didn't load", systemImage: "icloud.slash")
            } description: {
                Text(problem)
            } actions: {
                Button("Try again") { Task { await load() } }
            }
        } else if visible.isEmpty && !isLoading {
            ContentUnavailableView {
                Label(query.isEmpty ? LocalizedStringKey("No routes yet") : LocalizedStringKey("Nothing in this town yet"),
                      systemImage: "person.2")
            } description: {
                Text("Make a route of your own and publish it — your town, your favourite places, your stories.")
            } actions: {
                Button("Publish a route") { choosesRoute = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func load() async {
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                routes = try await model.community.search(city: text)
            } else if feed == .nearby {
                guard let location = await model.trip.location.currentLocation() else {
                    routes = []
                    problem = String(localized: "Allow Recorrido to use your location to see routes nearby.")
                    return
                }
                routes = try await model.community.nearby(Coordinate(location.coordinate))
            } else {
                routes = try await model.community.latest()
            }
        } catch {
            routes = []
            problem = CommunityView.message(for: error)
        }
    }

    /// A human explanation of a CloudKit failure; `nil` when there is simply nothing yet.
    static func message(for error: Error) -> String? {
        if let error = error as? CommunityError { return error.localizedDescription }
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .unknownItem:
            // The record type appears with the first published route.
            return nil
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return String(localized: "No connection to iCloud. Check the internet and try again.")
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud in the iPhone settings to publish routes.")
        case .invalidArguments:
            return String(localized: "The feed isn't set up yet: its indexes are missing in the CloudKit Console (see README).")
        default:
            return error.localizedDescription
        }
    }
}

/// One published route in a list.
struct CommunityRow: View {
    let item: CommunityRoute

    var body: some View {
        HStack(spacing: 12) {
            EmojiTile(emoji: item.emoji, seed: item.id, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text([item.city, item.country].compactMap { $0?.nilIfEmpty }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: item.isMine ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    Text(item.authorName)
                    Text(verbatim: "·")
                    Text("\(item.stopCount) stops")
                    if item.dayCount > 1 {
                        Text(verbatim: "·")
                        Text("\(item.dayCount) days")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A published route opened from the feed, with report and block.
struct CommunityRouteScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: CommunityRoute

    @State private var reports = false
    @State private var blocks = false

    var body: some View {
        Group {
            if let route = try? item.route() {
                RouteDetailView(route: model.catalog.enrich(route), mode: .preview)
            } else {
                ContentUnavailableView("This route can't be opened",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("It may have been made by a newer version of Recorrido."))
            }
        }
        .toolbar {
            if !item.isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            reports = true
                        } label: {
                            Label("Report the route", systemImage: "flag")
                        }
                        if item.authorID != nil {
                            Button(role: .destructive) {
                                blocks = true
                            } label: {
                                Label("Hide routes by \(item.authorName)", systemImage: "hand.raised")
                            }
                        }
                    } label: {
                        Image(systemName: "flag")
                    }
                    .accessibilityLabel(Text("Report or hide"))
                }
            }
        }
        .confirmationDialog("What is wrong with the route?", isPresented: $reports, titleVisibility: .visible) {
            ForEach(CommunityReportReason.allCases, id: \.self) { reason in
                Button(reason.title) { report(reason) }
            }
        } message: {
            Text("The route disappears from your feed right away, and we review every report.")
        }
        .confirmationDialog("Hide every route by \(item.authorName)?", isPresented: $blocks, titleVisibility: .visible) {
            Button("Hide", role: .destructive) {
                if let author = item.authorID { model.library.block(author: author) }
                dismiss()
            }
        } message: {
            Text("You can show them again in Settings.")
        }
    }

    private func report(_ reason: CommunityReportReason) {
        model.library.hide(record: item.id)
        let item = item
        let community = model.community
        Task { try? await community.report(item, reason: reason.rawValue) }
        dismiss()
    }
}

enum CommunityReportReason: String, CaseIterable {
    case offensive, spam, dangerous, wrong, other

    var title: LocalizedStringKey {
        switch self {
        case .offensive: "Offensive or hateful"
        case .spam: "Spam or advertising"
        case .dangerous: "Dangerous advice"
        case .wrong: "Wrong places or facts"
        case .other: "Something else"
        }
    }
}

/// Community routes of one town, shown on the town's page.
struct CommunityCitySection: View {
    @Environment(AppModel.self) private var model
    let city: City
    @State private var routes: [CommunityRoute] = []

    var body: some View {
        let visible = model.visibleCommunityRoutes(routes)
        VStack(alignment: .leading, spacing: 12) {
            if !visible.isEmpty {
                Text("From travellers").font(.title3.bold())
                ForEach(visible.prefix(6)) { item in
                    NavigationLink(value: item) {
                        CommunityRow(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: city.id) {
            routes = (try? await model.community.routes(inCity: city.searchTerms + [city.name])) ?? []
        }
    }
}

/// Picks one of the user's own routes to publish.
struct PublishPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (Route) -> Void

    var body: some View {
        let routes = model.library.routes.filter { $0.source == .user || $0.source == .generated }
        NavigationStack {
            List(routes) { route in
                Button {
                    onPick(model.latest(route))
                } label: {
                    HStack {
                        RouteListRow(route: route)
                        Spacer()
                        if model.library.publication(for: route.id) != nil {
                            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("No routes of your own yet", systemImage: "pencil.and.list.clipboard")
                    } description: {
                        Text("Create a route in My routes, or make your own version of any catalog route — then publish it here.")
                    }
                }
            }
            .navigationTitle("Which route?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The feed's rules, accepted once before the first publication.
struct CommunityRules: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rules of the feed").font(.headline)
            rule("Publish only your own routes and stories.")
            rule("No insults, hatred, advertising or dangerous advice.")
            rule("Don't publish other people's private details: home addresses, phone numbers.")
            rule("Routes that get reports are reviewed; they can be removed and their authors blocked.")
        }
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal").foregroundStyle(Color.accentColor)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Publishes a route, updates it or takes it down.
struct PublishRouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: Route

    @AppStorage(SettingsKey.communityAuthor, store: AppGroup.defaults) private var author = ""
    @AppStorage(SettingsKey.communityRulesAccepted, store: AppGroup.defaults) private var rulesAccepted = false
    @State private var isWorking = false
    @State private var problem: String?
    @State private var isPublished = false

    private var publication: Publication? {
        model.library.publication(for: route.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !rulesAccepted {
                    Section {
                        CommunityRules()
                    }
                    Section {
                        Button("I accept the rules") { rulesAccepted = true }
                    }
                } else {
                    Section {
                        RouteListRow(route: route)
                    }
                    Section {
                        TextField("Your name or nickname", text: $author)
                            .textContentType(.nickname)
                    } header: {
                        Text("Author")
                    } footer: {
                        Text("Shown next to the route.")
                    }
                    Section {
                        Button {
                            Task { await publish() }
                        } label: {
                            HStack {
                                Text(publication == nil ? LocalizedStringKey("Publish") : LocalizedStringKey("Update in the feed"))
                                if isWorking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isWorking || author.trimmingCharacters(in: .whitespaces).isEmpty)
                        if publication != nil {
                            Button("Remove from the feed", role: .destructive) {
                                Task { await unpublish() }
                            }
                            .disabled(isWorking)
                        }
                    } footer: {
                        Text("Everyone using Recorrido will see the route, its stops and your stories. You can remove it at any time.")
                    }
                    if let problem {
                        Section {
                            Text(problem).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(publication == nil ? LocalizedStringKey("Publish to the feed") : LocalizedStringKey("In the feed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("The route is in the feed", isPresented: $isPublished) {
                Button("OK") { dismiss() }
            } message: {
                Text("Travellers will find it in the feed and on the town's page.")
            }
        }
    }

    private func publish() async {
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await model.community.publish(model.latest(route), author: name, replacing: publication)
            model.library.setPublication(result, for: route.id)
            isPublished = true
        } catch {
            problem = CommunityView.message(for: error) ?? error.localizedDescription
        }
    }

    private func unpublish() async {
        guard let publication else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            try await model.community.unpublish(publication)
            model.library.setPublication(nil, for: route.id)
            dismiss()
        } catch {
            problem = CommunityView.message(for: error) ?? error.localizedDescription
        }
    }
}

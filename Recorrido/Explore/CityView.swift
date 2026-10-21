import MapKit
import SwiftUI

struct CityView: View {
    @Environment(AppModel.self) private var model
    let city: City
    @State private var webPage: WebPage?

    var body: some View {
        let routes = model.catalog.routes(inCity: city.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !routes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Routes").font(.title3.bold())
                        ForEach(routes) { route in
                            NavigationLink(value: route) {
                                RouteCard(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let gettingThere = city.gettingThere {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Getting there", systemImage: "car.side")
                            .font(.headline)
                        Text(gettingThere)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                Button {
                    model.generatorLaunch = GeneratorLaunch(townName: city.name, coordinate: city.coordinate)
                } label: {
                    Label("Build my own route here", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if let title = city.wikiTitle, let language = city.wikiLanguage,
                   let url = WikipediaClient.articleURL(language: language, title: title) {
                    Button {
                        webPage = WebPage(url: url)
                    } label: {
                        Label("About the town on Wikipedia", systemImage: "book")
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(city.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                EmojiTile(emoji: city.emoji, seed: city.id, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(city.name).font(.largeTitle.bold())
                    Text([city.region, city.country].compactMap { $0 }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let hint = model.distanceHint(for: city.coordinate) {
                        Text(hint).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
                }
            }
            Text(city.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

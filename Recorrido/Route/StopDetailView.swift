import MapKit
import SwiftUI

/// Everything about one stop: photo, the guide's story and games, tip,
/// audio guide, directions.
struct StopDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    let route: Route

    @State private var lookAround: MKLookAroundScene?
    @State private var webPage: WebPage?

    private var audio: AudioGuide { model.trip.audio }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = model.media.imageURL(for: stop) {
                        RemotePhoto(url: url, symbol: stop.category.symbol)
                            .frame(height: 230)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        Label(stop.category.title, systemImage: stop.category.symbol)
                            .foregroundStyle(stop.category.tint)
                        if stop.visitMinutes > 0 {
                            Text(verbatim: "·")
                            Label(Format.duration(minutes: Double(stop.visitMinutes)), systemImage: "clock")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                    Text(stop.title)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    if !stop.details.isEmpty {
                        Text(stop.details)
                            .font(stop.guide == nil ? .body : .callout)
                            .foregroundStyle(stop.guide == nil ? Color.primary : Color.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    buttons

                    if let guide = stop.guide {
                        StopGuideView(stop: stop, guide: guide)
                    }

                    if let tip = stop.tip {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local tip").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                Text(tip).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let address = stop.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let lookAround {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Look around").font(.headline)
                            LookAroundPreview(initialScene: lookAround)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    if stop.wikiTitle != nil || stop.imageURL != nil {
                        Text("Photo: Wikipedia / Wikimedia Commons, CC BY-SA.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await model.media.prefetch([stop])
                lookAround = try? await MKLookAroundSceneRequest(coordinate: stop.coordinate.cl).scene
            }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                audio.toggle(id: stop.id, text: AudioGuide.script(for: stop), language: route.language)
            } label: {
                Label(audio.isSpeaking(stop.id) ? LocalizedStringKey("Pause") : LocalizedStringKey("Listen"),
                      systemImage: audio.isSpeaking(stop.id) ? "pause.fill" : "headphones")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                stop.openDirections(mode: stop.arrivalMode)
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let title = stop.wikiTitle, let language = stop.wikiLanguage,
               let url = WikipediaClient.articleURL(language: language, title: title) {
                Button {
                    webPage = WebPage(url: url)
                } label: {
                    Image(systemName: "book")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Read on Wikipedia"))
            }
        }
        .controlSize(.large)
    }
}

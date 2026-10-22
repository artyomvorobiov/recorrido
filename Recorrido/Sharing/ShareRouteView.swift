import SwiftUI

/// All the ways to pass a route on: link, QR code, file and picture.
struct ShareRouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: Route
    let dayIndex: Int
    let directions: RouteDirections

    @State private var link: URL?
    @State private var qrImage: UIImage?
    @State private var poster: UIImage?
    @State private var isRenderingPoster = false
    @State private var publishes = false

    /// Own routes can go to the community feed.
    private var canPublish: Bool {
        model.community.isAvailable && model.isInLibrary(route) && (route.source == .user || route.source == .generated)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    qrCard

                    VStack(spacing: 10) {
                        if let link {
                            ShareLink(item: link, subject: Text(route.title), message: Text(message)) {
                                row("Send a link", detail: "Opens in the app or in any browser", symbol: "link")
                            }
                        }
                        ShareLink(item: RouteFile(route: route), preview: SharePreview(Text(route.title))) {
                            row("Send as a file", detail: "For AirDrop, Telegram, WhatsApp, e-mail", symbol: "doc.fill")
                        }
                        posterRow
                        if canPublish {
                            Button {
                                publishes = true
                            } label: {
                                if model.library.publication(for: route.id) == nil {
                                    row("Publish in the feed", detail: "Every Recorrido traveller will see it", symbol: "person.2.fill")
                                } else {
                                    row("In the feed", detail: "Update it or take it down", symbol: "checkmark.icloud.fill")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Share the route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { prepare() }
            .sheet(isPresented: $publishes) {
                PublishRouteView(route: route)
            }
        }
    }

    private var message: String {
        String(localized: "A route in \(route.city): \(route.title)")
    }

    private var qrCard: some View {
        VStack(spacing: 12) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Let a friend scan it with the iPhone camera")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 60))
                    .foregroundStyle(.tertiary)
                Text("The route is too long for a QR code — send a link or a file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    @ViewBuilder
    private var posterRow: some View {
        if let poster {
            ShareLink(item: Image(uiImage: poster), preview: SharePreview(Text(route.title), image: Image(uiImage: poster))) {
                row("Share as a picture", detail: "A map with the stops — for stories and chats", symbol: "photo.fill")
            }
        } else {
            Button {
                Task {
                    isRenderingPoster = true
                    poster = await RoutePoster.render(route: route, dayIndex: dayIndex,
                                                      legs: directions.geometry(for: route.days[safe: dayIndex]?.stops ?? []))
                    isRenderingPoster = false
                }
            } label: {
                row("Make a picture", detail: "A map with the stops — for stories and chats", symbol: "photo")
                    .overlay(alignment: .trailing) {
                        if isRenderingPoster { ProgressView().padding(.trailing, 16) }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isRenderingPoster)
        }
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 14)
    }

    private func prepare() {
        link = try? ShareCodec.link(for: route, base: AppConfig.webViewerURL)
        // The QR code holds as much text as fits.
        for detail in ShareCodec.Detail.allCases {
            if let url = try? ShareCodec.link(for: route, base: AppConfig.webViewerURL, detail: detail),
               url.absoluteString.utf8.count < 2800,
               let image = QRCode.image(for: url.absoluteString) {
                qrImage = image
                return
            }
        }
    }
}

/// A received route: look before saving.
struct ImportRouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: Route

    var body: some View {
        NavigationStack {
            RouteDetailView(route: route, mode: .preview)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            dismiss()
                            model.saveImported(route)
                        }
                    }
                }
        }
    }
}

import MapKit
import SwiftUI

/// Numbered stops and the paths between them.
struct RouteMapView: View {
    let stops: [Stop]
    let directions: RouteDirections
    var interactive = true
    var showsUser = false
    /// Stops already visited are drawn grey.
    var visited: Set<String> = []
    var highlighted: String?
    var onSelect: ((Stop) -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var selection: String?

    private struct Line: Identifiable {
        let id: Int
        let points: [CLLocationCoordinate2D]
        let tint: Color
        let dashed: Bool
    }

    private var lines: [Line] {
        directions.geometry(for: stops).enumerated().map { index, leg in
            let mode = stops[index + 1].arrivalMode
            return Line(
                id: index,
                points: leg.points.map(\.cl),
                tint: mode.tint,
                dashed: leg.isEstimate || mode.isPublicTransport
            )
        }
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : [], selection: $selection) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.points)
                    .stroke(line.tint.opacity(0.85),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: line.dashed ? [1, 9] : []))
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.title, coordinate: stop.coordinate.cl, anchor: .center) {
                    StopBadge(
                        number: index + 1,
                        tint: stop.category.tint,
                        size: stop.id == highlighted ? 38 : 28,
                        isDone: visited.contains(stop.id)
                    )
                }
                .annotationTitles(.hidden)
                .tag(stop.id)
            }
            if showsUser {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if interactive {
                MapCompass()
                MapScaleView()
                if showsUser { MapUserLocationButton() }
            }
        }
        .onChange(of: selection) { _, id in
            guard let id, let stop = stops.first(where: { $0.id == id }) else { return }
            onSelect?(stop)
            selection = nil
        }
        .onChange(of: stops.map(\.id)) { _, _ in
            withAnimation { position = .automatic }
        }
    }
}

/// The route map on the whole screen.
struct FullRouteMap: View {
    let title: String
    let stops: [Stop]
    let directions: RouteDirections
    var onSelect: ((Stop) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RouteMapView(stops: stops, directions: directions, interactive: true, showsUser: true) { stop in
                dismiss()
                onSelect?(stop)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

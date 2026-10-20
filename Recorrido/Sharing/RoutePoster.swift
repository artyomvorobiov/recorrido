import MapKit
import SwiftUI

/// A good-looking picture of a route for stories and chats.
@MainActor
enum RoutePoster {
    static func render(route: Route, dayIndex: Int, legs: [LegGeometry]) async -> UIImage? {
        guard let day = route.days[safe: dayIndex], !day.stops.isEmpty else { return nil }
        let mapSize = CGSize(width: 540, height: 540)
        let map = await mapImage(stops: day.stops, legs: legs, size: mapSize)
        let poster = PosterView(route: route, day: day, dayIndex: dayIndex, map: map)
            .frame(width: 540, height: 960)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        return renderer.uiImage
    }

    private static func mapImage(stops: [Stop], legs: [LegGeometry], size: CGSize) async -> UIImage? {
        let points = stops.map(\.coordinate) + legs.flatMap(\.points)
        guard let region = MKCoordinateRegion(fitting: points, margin: 1.5) else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for (index, leg) in legs.enumerated() {
                let mode = stops[safe: index + 1]?.arrivalMode ?? .walk
                let path = UIBezierPath()
                for (pointIndex, coordinate) in leg.points.enumerated() {
                    let point = snapshot.point(for: coordinate.cl)
                    if pointIndex == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineWidth = 5
                if leg.isEstimate || mode.isPublicTransport {
                    path.setLineDash([2, 9], count: 2, phase: 0)
                }
                UIColor(mode.tint).withAlphaComponent(0.9).setStroke()
                path.stroke()
            }
            for (index, stop) in stops.enumerated() {
                let center = snapshot.point(for: stop.coordinate.cl)
                let rect = CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)
                let circle = UIBezierPath(ovalIn: rect)
                UIColor(stop.category.tint).setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                let text = "\(index + 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attributes)
            }
        }
    }
}

private struct PosterView: View {
    let route: Route
    let day: RouteDay
    let dayIndex: Int
    let map: UIImage?

    var body: some View {
        let estimate = RouteEstimator.day(day)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let map {
                    Image(uiImage: map).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 540, height: 470)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(route.emoji).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(2)
                        Text(subtitle(estimate))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(day.stops.prefix(9).enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 10) {
                            StopBadge(number: index + 1, tint: stop.category.tint, size: 24)
                            Text(stop.title)
                                .font(.system(size: 17, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    if day.stops.count > 9 {
                        Text(verbatim: "+ \(day.stops.count - 9)")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 34)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Text(verbatim: "Recorrido")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    ModeIcons(modes: route.modes)
                        .font(.system(size: 16))
                }
            }
            .padding(24)
            .frame(width: 540, height: 490, alignment: .topLeading)
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private func subtitle(_ estimate: DayEstimate) -> String {
        var parts = [route.city]
        if route.days.count > 1 {
            parts.append(String(localized: "Day \(dayIndex + 1)"))
        }
        parts.append(Format.duration(minutes: estimate.totalMinutes))
        parts.append(Format.distance(estimate.distance))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

import MapKit
import SwiftUI

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var cl: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKMultiPoint {
    var coordinateList: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}

extension MKCoordinateRegion {
    /// A region showing all the points with some margin.
    init?(fitting points: [Coordinate], margin: Double = 1.35, minimumSpan: Double = 0.006) {
        guard let box = Geo.boundingBox(of: points) else { return nil }
        self.init(
            center: box.center.cl,
            span: MKCoordinateSpan(
                latitudeDelta: max(box.latitudeSpan * margin, minimumSpan),
                longitudeDelta: max(box.longitudeSpan * margin, minimumSpan)
            )
        )
    }
}

extension Stop {
    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.cl))
        item.name = title
        return item
    }

    /// Opens Apple Maps with directions to this stop.
    func openDirections(mode: TransportMode) {
        let directions: String
        switch mode {
        case .car: directions = MKLaunchOptionsDirectionsModeDriving
        case .walk, .bike: directions = MKLaunchOptionsDirectionsModeWalking
        default: directions = MKLaunchOptionsDirectionsModeTransit
        }
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: directions])
    }
}

extension Route {
    /// Google Maps directions through the stops of a day (handy to hand over
    /// to a friend who drives).
    func googleMapsURL(day index: Int) -> URL? {
        guard days.indices.contains(index) else { return nil }
        let stops = days[index].stops
        guard let first = stops.first, let last = stops.last, stops.count > 1 else { return nil }
        func text(_ stop: Stop) -> String { "\(stop.coordinate.latitude),\(stop.coordinate.longitude)" }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: text(first)),
            URLQueryItem(name: "destination", value: text(last)),
            URLQueryItem(name: "travelmode", value: modes.contains(.car) ? "driving" : "walking"),
        ]
        let middle = stops.dropFirst().dropLast().prefix(8).map(text)
        if !middle.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: middle.joined(separator: "|")))
        }
        components.queryItems = items
        return components.url
    }
}

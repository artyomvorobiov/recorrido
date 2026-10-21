import Foundation

/// A point on Earth. Kept independent from CoreLocation so the core logic can
/// be unit-tested anywhere Foundation runs.
struct Coordinate: Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ latitude: Double, _ longitude: Double) {
        self.init(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    /// Copy rounded to the given number of decimal digits (5 digits ≈ 1 m).
    func rounded(toDigits digits: Int) -> Coordinate {
        let factor = pow(10.0, Double(digits))
        return Coordinate((latitude * factor).rounded() / factor, (longitude * factor).rounded() / factor)
    }
}

extension Coordinate: Codable {
    private enum CodingKeys: String, CodingKey {
        case lat, lon, latitude, longitude
    }

    /// Accepts `[lat, lon]`, `{"lat":…, "lon":…}` and `{"latitude":…, "longitude":…}`.
    init(from decoder: Decoder) throws {
        if var pair = try? decoder.unkeyedContainer() {
            let latitude = try pair.decode(Double.self)
            let longitude = try pair.decode(Double.self)
            self.init(latitude: latitude, longitude: longitude)
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
                ?? container.decode(Double.self, forKey: .lat)
            let longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
                ?? container.decode(Double.self, forKey: .lon)
            self.init(latitude: latitude, longitude: longitude)
        }
    }

    /// Always written as a compact `[lat, lon]` pair.
    func encode(to encoder: Encoder) throws {
        var pair = encoder.unkeyedContainer()
        try pair.encode(latitude)
        try pair.encode(longitude)
    }
}

/// Spherical geometry helpers. Accuracy is more than enough at city scale.
enum Geo {
    static let earthRadius: Double = 6_371_000

    /// Great-circle distance in meters.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b` in degrees clockwise from north, 0..<360.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `distance` meters away from `origin` heading along `bearing` degrees.
    static func destination(from origin: Coordinate, distance: Double, bearing: Double) -> Coordinate {
        let delta = distance / earthRadius
        let theta = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(delta) * cos(lat1), cos(delta) - sin(lat1) * sin(lat2))
        let longitude = (lon2 * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180
        return Coordinate(lat2 * 180 / .pi, longitude)
    }

    static func centroid(of points: [Coordinate]) -> Coordinate? {
        guard !points.isEmpty else { return nil }
        let count = Double(points.count)
        return Coordinate(
            points.reduce(0) { $0 + $1.latitude } / count,
            points.reduce(0) { $0 + $1.longitude } / count
        )
    }

    /// Length of a polyline in meters.
    static func pathLength(_ points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    struct Box: Hashable, Sendable {
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double

        var center: Coordinate {
            Coordinate((minLatitude + maxLatitude) / 2, (minLongitude + maxLongitude) / 2)
        }
        var latitudeSpan: Double { maxLatitude - minLatitude }
        var longitudeSpan: Double { maxLongitude - minLongitude }
    }

    static func boundingBox(of points: [Coordinate]) -> Box? {
        guard let first = points.first else { return nil }
        var box = Box(minLatitude: first.latitude, maxLatitude: first.latitude,
                      minLongitude: first.longitude, maxLongitude: first.longitude)
        for point in points.dropFirst() {
            box.minLatitude = min(box.minLatitude, point.latitude)
            box.maxLatitude = max(box.maxLatitude, point.latitude)
            box.minLongitude = min(box.minLongitude, point.longitude)
            box.maxLongitude = max(box.maxLongitude, point.longitude)
        }
        return box
    }

    /// Thins a dense polyline (e.g. walking directions) keeping its shape
    /// within `tolerance` meters. Douglas–Peucker on an equirectangular projection.
    static func simplify(_ points: [Coordinate], tolerance: Double) -> [Coordinate] {
        guard points.count > 2 else { return points }
        let reference = points[0].latitude * .pi / 180
        let scaleX = cos(reference) * earthRadius * .pi / 180
        let scaleY = earthRadius * .pi / 180
        let projected = points.map { (x: $0.longitude * scaleX, y: $0.latitude * scaleY) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let a = projected[start]
            let b = projected[end]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            var farthest = start
            var farthestDistance = 0.0
            for index in (start + 1)..<end {
                let p = projected[index]
                let d: Double
                if length < 1e-9 {
                    d = ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
                } else {
                    d = abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
                }
                if d > farthestDistance {
                    farthestDistance = d
                    farthest = index
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}

import XCTest
@testable import RecorridoCore

final class GeoTests: XCTestCase {
    func testDistanceBetweenMoscowAndSaintPetersburg() {
        let redSquare = Coordinate(55.7539, 37.6208)
        let palaceSquare = Coordinate(59.9390, 30.3158)
        XCTAssertEqual(Geo.distance(redSquare, palaceSquare) / 1000, 634, accuracy: 5)
    }

    func testBearingPointsNorthAndEast() {
        let origin = Coordinate(55.0, 37.0)
        XCTAssertEqual(Geo.bearing(from: origin, to: Coordinate(56.0, 37.0)), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: origin, to: Coordinate(55.0, 38.0)), 90, accuracy: 1)
    }

    func testDestinationRoundTrip() {
        let origin = Coordinate(56.4196, 40.4492)
        let target = Geo.destination(from: origin, distance: 2500, bearing: 135)
        XCTAssertEqual(Geo.distance(origin, target), 2500, accuracy: 1)
        XCTAssertEqual(Geo.bearing(from: origin, to: target), 135, accuracy: 0.5)
    }

    func testSimplifyKeepsEndsAndDropsCollinearPoints() {
        let line = (0...20).map { Coordinate(56.0 + Double($0) * 0.0001, 40.0) }
        let simplified = Geo.simplify(line, tolerance: 1)
        XCTAssertEqual(simplified.count, 2)
        XCTAssertEqual(simplified.first, line.first)
        XCTAssertEqual(simplified.last, line.last)
    }

    func testCoordinateDecodesSeveralShapes() throws {
        let decoder = JSONDecoder()
        let pair = try decoder.decode(Coordinate.self, from: Data("[56.1, 40.2]".utf8))
        let short = try decoder.decode(Coordinate.self, from: Data(#"{"lat": 56.1, "lon": 40.2}"#.utf8))
        let long = try decoder.decode(Coordinate.self, from: Data(#"{"latitude": 56.1, "longitude": 40.2}"#.utf8))
        XCTAssertEqual(pair, short)
        XCTAssertEqual(pair, long)
        let encoded = String(decoding: try JSONEncoder().encode(pair), as: UTF8.self)
        XCTAssertEqual(encoded, "[56.1,40.2]")
    }
}

final class PlannerTests: XCTestCase {
    /// Points along a street, given in a shuffled order.
    private let street: [Coordinate] = [0, 4, 1, 3, 2].map { Coordinate(56.0, 40.0 + Double($0) * 0.005) }

    func testOrdersPointsAlongALine() {
        let order = RoutePlanner.orderedIndices(of: street, start: nil, returnToStart: false)
        let longitudes = order.map { street[$0].longitude }
        XCTAssertTrue(longitudes == longitudes.sorted() || longitudes == longitudes.sorted().reversed())
    }

    func testStartsFromTheGivenPoint() {
        let start = Coordinate(56.0, 40.03)
        let order = RoutePlanner.orderedIndices(of: street, start: start, returnToStart: false)
        XCTAssertEqual(street[order[0]].longitude, 40.02, accuracy: 1e-9)
        XCTAssertEqual(Set(order), Set(street.indices))
    }

    func testOptimizeKeepsTheFirstStop() {
        let stops = street.enumerated().map { index, point in Stop(id: "\(index)", title: "\(index)", coordinate: point) }
        let optimized = RoutePlanner.optimize(stops, keepFirst: true)
        XCTAssertEqual(optimized.first?.id, "0")
        // Longitudes: id0 40.000, id2 40.005, id4 40.010, id3 40.015, id1 40.020.
        XCTAssertEqual(optimized.map(\.id), ["0", "2", "4", "3", "1"])
    }

    func testSingleDayFitsTheBudget() {
        let candidates = (0..<30).map { index in
            PlannerCandidate(
                id: "p\(index)",
                coordinate: Coordinate(56.42 + Double(index % 6) * 0.003, 40.44 + Double(index / 6) * 0.004),
                score: Double(30 - index),
                visitMinutes: 30
            )
        }
        var options = PlannerOptions()
        options.minutesPerDay = 240
        let plan = RoutePlanner.plan(candidates, options: options)
        XCTAssertEqual(plan.count, 1)
        let day = plan[0]
        XCTAssertFalse(day.isEmpty)
        XCTAssertLessThanOrEqual(RoutePlanner.cost(of: day, options: options), 240)
        XCTAssertTrue(day.contains { $0.id == "p0" }, "the best place should be picked")
    }

    func testTwoDaysSplitTwoAreas() {
        // Two clusters 6 km apart.
        let west = (0..<6).map { PlannerCandidate(id: "w\($0)", coordinate: Coordinate(55.75, 37.55 + Double($0) * 0.002), score: 5, visitMinutes: 40) }
        let east = (0..<6).map { PlannerCandidate(id: "e\($0)", coordinate: Coordinate(55.75, 37.65 + Double($0) * 0.002), score: 4, visitMinutes: 40) }
        var options = PlannerOptions()
        options.days = 2
        options.minutesPerDay = 360
        options.mobility = .transit
        let plan = RoutePlanner.plan(west + east, options: options)
        XCTAssertEqual(plan.count, 2)
        for day in plan {
            let prefixes = Set(day.map { $0.id.prefix(1) })
            XCTAssertEqual(prefixes.count, 1, "each day should stay in one area: \(day.map(\.id))")
        }
    }

    func testMobilityChoosesTransportForLongHops() {
        XCTAssertEqual(Mobility.car.mode(forDistance: 800, pace: .normal), .walk)
        XCTAssertEqual(Mobility.car.mode(forDistance: 5000, pace: .normal), .car)
        XCTAssertEqual(Mobility.transit.mode(forDistance: 5000, pace: .normal), .transit)
        XCTAssertEqual(Mobility.walking.mode(forDistance: 5000, pace: .normal), .walk)
    }

    func testEstimatesUseArrivalModes() {
        let day = RouteDay(stops: [
            Stop(title: "A", coordinate: Coordinate(56.42, 40.44), visitMinutes: 30),
            Stop(title: "B", coordinate: Coordinate(56.43, 40.44), visitMinutes: 30),
            Stop(title: "C", coordinate: Coordinate(56.47, 40.50), visitMinutes: 30, arrival: Arrival(mode: .car)),
        ])
        let estimate = RouteEstimator.day(day)
        XCTAssertEqual(estimate.legs.count, 2)
        XCTAssertEqual(estimate.legs[0].mode, .walk)
        XCTAssertEqual(estimate.legs[1].mode, .car)
        XCTAssertEqual(estimate.visitMinutes, 90, accuracy: 0.001)
        XCTAssertGreaterThan(estimate.walkingDistance, 1000)
    }
}

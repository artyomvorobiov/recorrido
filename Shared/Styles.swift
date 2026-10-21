import SwiftUI

extension TransportMode {
    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .bike: "bicycle"
        case .metro: "tram.fill.tunnel"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .train: "train.side.front.car"
        case .ferry: "ferry.fill"
        case .funicular: "cablecar"
        case .cableCar: "cablecar.fill"
        case .transit: "bus.doubledecker.fill"
        case .car: "car.fill"
        }
    }

    var title: String {
        switch self {
        case .walk: String(localized: "On foot")
        case .bike: String(localized: "Bike")
        case .metro: String(localized: "Metro")
        case .tram: String(localized: "Tram")
        case .bus: String(localized: "Bus")
        case .train: String(localized: "Train")
        case .ferry: String(localized: "Boat")
        case .funicular: String(localized: "Funicular")
        case .cableCar: String(localized: "Cable car")
        case .transit: String(localized: "Public transport")
        case .car: String(localized: "Car or taxi")
        }
    }

    var tint: Color {
        switch self {
        case .walk: .accentColor
        case .bike: .green
        case .metro: .red
        case .tram: .orange
        case .bus, .transit: .blue
        case .train: .indigo
        case .ferry: .cyan
        case .funicular, .cableCar: .teal
        case .car: .purple
        }
    }

    /// Whether directions draw a real path for this mode (otherwise a dashed line).
    var hasPathOnMap: Bool {
        switch self {
        case .walk, .bike, .car: true
        default: false
        }
    }
}

extension PlaceCategory {
    var symbol: String {
        switch self {
        case .landmark: "star.fill"
        case .museum: "building.columns.fill"
        case .church: "bell.fill"
        case .palace: "crown.fill"
        case .castle: "shield.fill"
        case .park: "leaf.fill"
        case .viewpoint: "binoculars.fill"
        case .square: "square.grid.2x2.fill"
        case .street: "road.lanes"
        case .bridge: "water.waves"
        case .monument: "figure.stand"
        case .market: "basket.fill"
        case .theater: "theatermasks.fill"
        case .district: "map.fill"
        case .nature: "mountain.2.fill"
        case .food: "fork.knife"
        case .other: "mappin"
        }
    }

    var title: String {
        switch self {
        case .landmark: String(localized: "Landmark")
        case .museum: String(localized: "Museum")
        case .church: String(localized: "Church")
        case .palace: String(localized: "Palace or estate")
        case .castle: String(localized: "Fortress")
        case .park: String(localized: "Park")
        case .viewpoint: String(localized: "Viewpoint")
        case .square: String(localized: "Square")
        case .street: String(localized: "Street")
        case .bridge: String(localized: "Bridge")
        case .monument: String(localized: "Monument")
        case .market: String(localized: "Market")
        case .theater: String(localized: "Theatre")
        case .district: String(localized: "Neighbourhood")
        case .nature: String(localized: "Nature")
        case .food: String(localized: "Food")
        case .other: String(localized: "Place")
        }
    }

    var tint: Color {
        switch self {
        case .landmark: .orange
        case .museum: .purple
        case .church: Color(red: 0.80, green: 0.56, blue: 0.10)
        case .palace: .pink
        case .castle: .brown
        case .park: .green
        case .viewpoint: .teal
        case .square: .blue
        case .street: .gray
        case .bridge: .cyan
        case .monument: .red
        case .market: .mint
        case .theater: .indigo
        case .district: .gray
        case .nature: Color(red: 0.20, green: 0.55, blue: 0.30)
        case .food: .orange
        case .other: .gray
        }
    }
}

extension Pace {
    var title: String {
        switch self {
        case .relaxed: String(localized: "Relaxed")
        case .normal: String(localized: "Normal")
        case .active: String(localized: "Active")
        }
    }
}

extension Mobility {
    var title: String {
        switch self {
        case .walking: String(localized: "Only on foot")
        case .transit: String(localized: "On foot + public transport")
        case .car: String(localized: "On foot + car or taxi")
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .transit: "bus.fill"
        case .car: "car.fill"
        }
    }
}

extension Color {
    /// A soft background for a route's emoji, stable for the same seed.
    static func tile(for seed: String) -> Color {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.35, brightness: 0.95)
    }
}

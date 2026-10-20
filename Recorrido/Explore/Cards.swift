import SwiftUI

struct CityCard: View {
    @Environment(AppModel.self) private var model
    let city: City

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiTile(emoji: city.emoji, seed: city.id, size: 46)
            Text(city.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let region = city.region {
                Text(region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let hint = model.distanceHint(for: city.coordinate) {
                Text(hint)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card(padding: 14)
    }
}

struct CityRow: View {
    let city: City

    var body: some View {
        HStack(spacing: 14) {
            EmojiTile(emoji: city.emoji, seed: city.id, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name).font(.headline)
                Text([city.region, city.country].compactMap { $0 }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }
}

struct RouteCard: View {
    let route: Route

    var body: some View {
        let estimate = RouteEstimator.route(route)
        HStack(alignment: .top, spacing: 14) {
            EmojiTile(emoji: route.emoji, seed: route.id, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(route.city)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(route.lengthLabel, systemImage: "clock")
                    Label(Format.distance(estimate.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label("\(route.stopCount)", systemImage: "mappin.and.ellipse")
                }
                .labelStyle(CompactLabelStyle())
                .font(.caption)
                .foregroundStyle(.secondary)
                ModeIcons(modes: route.modes)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// Icon and text close together.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

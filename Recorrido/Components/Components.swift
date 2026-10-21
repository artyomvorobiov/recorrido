import SafariServices
import SwiftUI

/// Rounded card background used across the app.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// A big emoji on a soft colored tile — the face of a route or a town.
struct EmojiTile: View {
    let emoji: String
    var seed: String = ""
    var size: CGFloat = 56

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Color.tile(for: seed.isEmpty ? emoji : seed).opacity(0.55),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Number in a circle, tinted by the kind of place — map pins and lists.
struct StopBadge: View {
    let number: Int
    var tint: Color = .accentColor
    var size: CGFloat = 28
    var isDone = false

    var body: some View {
        ZStack {
            Circle().fill(isDone ? Color.gray : tint)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .bold))
            } else {
                Text("\(number)")
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// Small icons of the transport a route uses.
struct ModeIcons: View {
    let modes: [TransportMode]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modes.prefix(4), id: \.self) { mode in
                Image(systemName: mode.symbol)
                    .foregroundStyle(mode.tint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(modes.map(\.title).joined(separator: ", "))
    }
}

/// "value + caption" block for stats rows.
struct StatBlock: View {
    let value: String
    let caption: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(.secondary).font(.footnote)
                }
                Text(value).font(.headline).monospacedDigit()
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selectable capsule for options.
struct Chip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out in rows, wrapping like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A photo from the web with a calm placeholder.
struct RemotePhoto: View {
    let url: URL?
    var symbol: String = "photo"

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .tertiarySystemFill))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: symbol).font(.title).foregroundStyle(.tertiary)
                    default:
                        ProgressView()
                    }
                }
            } else {
                Image(systemName: symbol).font(.title).foregroundStyle(.tertiary)
            }
        }
        .clipped()
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Wraps a URL so it can drive `.sheet(item:)`.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Route {
    /// "2 days", "5 h 30 min".
    var lengthLabel: String {
        if days.count > 1 {
            return String(localized: "\(days.count) days")
        }
        return Format.duration(minutes: RouteEstimator.route(self).totalMinutes)
    }

    var hasWikipediaContent: Bool {
        allStops.contains { $0.wikiTitle != nil || $0.imageURL != nil }
    }
}

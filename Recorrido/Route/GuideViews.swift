import SwiftUI

/// The guide's story, paragraph by paragraph. Long stories open in full on request.
struct StoryText: View {
    let paragraphs: [String]
    /// Paragraphs shown before "Read more"; `nil` shows everything.
    var preview: Int?

    @State private var isExpanded = false

    var body: some View {
        let shown = isExpanded || preview == nil ? paragraphs : Array(paragraphs.prefix(preview ?? 0))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isExpanded, let preview, paragraphs.count > preview {
                Button {
                    withAnimation(.easeInOut) { isExpanded = true }
                } label: {
                    Label("Read more", systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// A titled block of the guide.
struct GuideSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Find with your own eyes": details to spot on the place, ticked off by tapping.
struct LookForCard: View {
    @Environment(AppModel.self) private var model
    let stop: Stop
    let items: [String]

    var body: some View {
        let progress = model.library.progress
        let found = items.indices.filter { progress.isFound(stop.guideKey, item: $0) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Find with your own eyes", systemImage: "eye")
                    .font(.headline)
                    .foregroundStyle(.teal)
                Spacer()
                Text("\(found) of \(items.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(found == items.count ? Color.green : Color.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let isFound = progress.isFound(stop.guideKey, item: index)
                Button {
                    withAnimation(.snappy) { model.library.toggleFound(stop, item: index) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isFound ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isFound ? Color.green : Color.secondary)
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(isFound ? Color.secondary : Color.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isFound ? .isSelected : [])
            }
            if found == items.count {
                Text("Everything found — a sharp eye!")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sensoryFeedback(.success, trigger: found) { old, new in new == items.count && new > old }
    }
}

/// "Did you know?" cards to swipe through.
struct FactsCarousel: View {
    let facts: [String]

    var body: some View {
        GuideSection(title: "Did you know?", symbol: "sparkles", tint: .purple) {
            if facts.count == 1, let fact = facts.first {
                card(fact, number: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                            card(fact, number: index + 1)
                                .frame(width: 270, alignment: .topLeading)
                        }
                    }
                    // Cards of one height, as tall as the longest fact.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func card(_ fact: String, number: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let number {
                Text(verbatim: "\(number)/\(facts.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
            }
            Text(fact)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A legend kept behind a tap, like a guide's "and now, a story…".
struct LegendCard: View {
    let text: String
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut) { isOpen.toggle() }
            } label: {
                HStack {
                    Label("Legend", systemImage: "book.closed")
                        .font(.headline)
                        .foregroundStyle(.brown)
                    Spacer()
                    Text(isOpen ? LocalizedStringKey("Hide") : LocalizedStringKey("Tell me"))
                        .font(.subheadline.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                Text(text)
                    .font(.callout)
                    .italic()
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.brown.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A question about the place. The first answer counts; the explanation follows.
struct QuizCard: View {
    @Environment(AppModel.self) private var model
    let stop: Stop
    let quiz: Quiz

    var body: some View {
        let chosen = model.library.progress.answers[stop.guideKey]
        VStack(alignment: .leading, spacing: 12) {
            Label("Question", systemImage: "questionmark.bubble")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(quiz.question)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                Button {
                    withAnimation(.snappy) { model.library.answer(stop, option: index) }
                } label: {
                    HStack(spacing: 10) {
                        Text(option)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let chosen, index == quiz.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if chosen == index {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                    .background(fill(for: index, chosen: chosen), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil)
            }
            if let chosen {
                Text(chosen == quiz.answer ? LocalizedStringKey("Right!") : LocalizedStringKey("Not quite."))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(chosen == quiz.answer ? Color.green : Color.orange)
                Text(quiz.explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sensoryFeedback(trigger: chosen) { _, new in
            guard let new else { return nil }
            return new == quiz.answer ? .success : .error
        }
    }

    private func fill(for index: Int, chosen: Int?) -> Color {
        guard let chosen else { return Color(uiColor: .tertiarySystemFill) }
        if index == quiz.answer { return Color.green.opacity(0.18) }
        if index == chosen { return Color.red.opacity(0.15) }
        return Color(uiColor: .tertiarySystemFill).opacity(0.6)
    }
}

/// What to notice on the way to a stop.
struct ApproachNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("On the way")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Every part of a stop's guide, in the order a guide would tell it.
struct StopGuideView: View {
    let stop: Stop
    let guide: StopGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let approach = guide.approach {
                ApproachNote(text: approach)
            }
            if !guide.paragraphs.isEmpty {
                GuideSection(title: "The story", symbol: "text.book.closed") {
                    StoryText(paragraphs: guide.paragraphs)
                }
            }
            if !guide.lookFor.isEmpty {
                LookForCard(stop: stop, items: guide.lookFor)
            }
            if !guide.facts.isEmpty {
                FactsCarousel(facts: guide.facts)
            }
            if let legend = guide.legend {
                LegendCard(text: legend)
            }
            if let quiz = guide.quiz {
                QuizCard(stop: stop, quiz: quiz)
            }
        }
    }
}

/// A town's guidebook page: story, history, food, souvenirs and advice.
struct CityGuideView: View {
    let guide: CityGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !guide.paragraphs.isEmpty {
                GuideSection(title: "About the town", symbol: "text.book.closed") {
                    StoryText(paragraphs: guide.paragraphs, preview: 2)
                }
            }
            if !guide.history.isEmpty {
                GuideSection(title: "History in brief", symbol: "hourglass", tint: .brown) {
                    Timeline(moments: guide.history)
                }
            }
            if !guide.taste.isEmpty {
                ListBlock(title: "Worth tasting", symbol: "fork.knife", tint: .orange, items: guide.taste)
            }
            if !guide.souvenirs.isEmpty {
                ListBlock(title: "To bring home", symbol: "gift", tint: .pink, items: guide.souvenirs)
            }
            if !guide.tips.isEmpty {
                ListBlock(title: "Good to know", symbol: "lightbulb", tint: .yellow, items: guide.tips)
            }
        }
    }

    private struct Timeline: View {
        let moments: [CityGuide.Moment]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(Color.brown)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                            if index < moments.count - 1 {
                                Rectangle()
                                    .fill(Color.brown.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moment.year)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.brown)
                            Text(moment.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 14)
                    }
                }
            }
            .card(padding: 14)
        }
    }

    private struct ListBlock: View {
        let title: LocalizedStringKey
        let symbol: String
        let tint: Color
        let items: [String]

        var body: some View {
            GuideSection(title: title, symbol: symbol, tint: tint) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 7)
                            Text(item)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
        }
    }
}

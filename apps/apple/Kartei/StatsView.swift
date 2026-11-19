// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Stats (stats.html). True retention leads (F7): how much you actually remembered against your target.
/// Then what is coming (minutes, not card counts), where the cards stand, and the leeches. No streaks (F6).
struct StatsView: View {
    let store: DeckStore
    @State private var model = StatsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topline
                if let s = model.snapshot {
                    content(s)
                } else if let e = model.error {
                    Meta("Stats could not be read: \(e)").padding(.top, 16)
                } else {
                    ProgressView().controlSize(.small).padding(.top, 24).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.bg)
        .onAppear { model.attach(store.backend); model.load() }
        .onChange(of: store.backend == nil) { model.attach(store.backend) }
    }

    private var topline: some View {
        HStack {
            Text("\(model.deckName ?? "All decks"), last 30 days").font(Type.body(13)).foregroundStyle(Ink.muted).lineLimit(1)
            Spacer()
            Menu {
                Button("All decks") { model.deckName = nil }
                ForEach(store.rows.filter { $0.depth == 0 && !$0.filtered }) { row in
                    Button(row.name) { model.deckName = row.name }
                }
            } label: {
                Text("Change").font(Type.body(13)).underline().foregroundStyle(Ink.muted).frame(minHeight: 44)
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            .accessibilityLabel("Change deck")
            .accessibilityValue(model.deckName ?? "All decks")
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private func content(_ s: StatsSnapshot) -> some View {
        headline(s).padding(.top, 8)
        RetentionChart(days: s.daily, target: s.target).padding(.top, 16)
        Meta(s.total == 0 ? "Once you review cards you already know, each day's share shows here."
                          : "Share of cards you got right on the first try each day, counting cards last seen a day or more before. Days with under 5 such reviews are left out.")
            .padding(.top, 6)

        VStack(spacing: 0) {
            FactRow(label: "Tomorrow", value: "\(s.forecast.count > 1 ? s.forecast[1].minutes : 0) min")
            if let recall = s.recallNow {
                FactRow(label: "Cards you'd recall today", value: "\(grouped(recall)) of \(grouped(s.recallOf))")
            }
        }
        .padding(.top, 16)

        HStack(alignment: .firstTextBaseline) {
            Caption("Next 14 days, minutes a day")
            Spacer()
            Meta(s.measuredTime ? "at your \(Int(s.secondsPerCard.rounded())) s a card" : "at 8 s a card until 50 answers")
        }
        .padding(.top, 20).padding(.bottom, 8)
        ForecastChart(days: s.forecast)
        Meta("Reviews already scheduled. New cards add to this.").padding(.top, 4)

        StateBar(parts: [
            .init(id: "New", count: s.newCards, colour: Ink.new),
            .init(id: "Learning", count: s.learning, colour: Ink.learning),
            .init(id: "Young", count: s.young, colour: Ink.muted),
            .init(id: "Mature", count: s.mature, colour: Ink.text),
        ])
        .padding(.top, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cards by state")
        Meta("Young cards come back within 3 weeks, mature ones later.\(s.suspended > 0 ? " \(grouped(s.suspended)) suspended cards are not counted." : "")")
            .padding(.top, 6)

        VStack(spacing: 0) {
            FactRow(label: "Reviews this week", value: grouped(s.reviewsThisWeek))
            FactRow(label: "Cards that keep slipping", value: grouped(s.leeches))
        }
        .padding(.top, 12)
        if s.leeches > 0 {
            Meta("Forgotten 8 times or more. Rewriting or splitting them works better than more reviews. Find them in Browse under Keep slipping.")
                .padding(.top, 6)
        }
    }

    private func headline(_ s: StatsSnapshot) -> some View {
        let target = Int((s.target * 100).rounded())
        let text: Text
        if let r = s.retention {
            text = Text("\(Int((r * 100).rounded()))% ").font(Type.display(34, heavy: true))
                + Text("remembered. Your target is \(target)%.").font(Type.display(34, heavy: false))
        } else {
            text = Text("Too few reviews yet. ").font(Type.display(34, heavy: true))
                + Text("Your target is \(target)%. This fills in after 20 reviews of known cards.").font(Type.display(34, heavy: false))
        }
        return text.foregroundStyle(Ink.display).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

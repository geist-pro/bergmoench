// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import WidgetKit

/// Reads the snapshot the app writes into the App Group. Never opens the collection.
struct TodayProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: ReachSnapshot?
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: context.isPreview ? (ReachShared.read() ?? Self.sample) : ReachShared.read()))
    }

    /// One entry now and one at each coming midnight the snapshot has a forecast for, so the numeral and the
    /// calendar roll over without the app. The app reloads the timeline whenever the counts change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = ReachShared.read()
        let cal = Calendar.current
        var entries = [Entry(date: .now, snapshot: snapshot)]
        let start = cal.startOfDay(for: .now)
        for offset in 1...max(1, (snapshot?.days.count ?? 1) - 1) {
            if let d = cal.date(byAdding: .day, value: offset, to: start) { entries.append(Entry(date: d, snapshot: snapshot)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample = ReachSnapshot(written: .now, studied: (0..<20).compactMap { i in
        Calendar.current.date(byAdding: .day, value: -[0, 1, 2, 4, 5, 7, 8, 9, 11, 12, 14, 15, 16, 18, 21, 22, 25, 28, 29, 32][i], to: .now).map { ReachSnapshot.dayKey($0) }
    }, days: [.init(day: ReachSnapshot.dayKey(.now), minutes: 12, cards: 54)])
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: TodayProvider.Entry

    var body: some View {
        let theme = entry.snapshot?.themeFamily ?? Palette.defaultFamily
        ReachWidgetContent(snapshot: entry.snapshot, date: entry.date, size: family == .systemSmall ? .small : .medium)
            .containerBackground(WidgetInk(theme, dark: scheme == .dark).bg, for: .widget)
    }
}

struct KarteiTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ReachShared.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Minutes of cards today and the days you studied in the last five weeks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct KarteiWidgetBundle: WidgetBundle {
    init() { WidgetType.register() }

    var body: some Widget { KarteiTodayWidget() }
}

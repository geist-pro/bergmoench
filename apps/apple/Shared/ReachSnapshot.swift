// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Shared by the app and the widget extension. The app writes this snapshot; the widget only reads it and never
// opens the collection.

import CoreText
import Foundation
import SwiftUI

/// What the widget shows: today's minutes and the five-week study calendar, plus a few days of forecast so the
/// numeral stays honest after midnight without the app running.
struct ReachSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable {
        /// Local calendar day, "yyyy-MM-dd".
        var day: String
        var minutes: Int
        var cards: Int
    }

    static let version = 1

    var version = ReachSnapshot.version
    var written: Date
    /// Days with at least one answer, as local "yyyy-MM-dd" days (absolute, so the calendar shifts correctly overnight).
    var studied: [String]
    /// Today first, then the following days, assuming nothing is studied in between.
    var days: [Day]
    /// The look chosen in the app ("gruvbox", "geist"). Optional so snapshots written before themes still decode;
    /// those draw in the default family.
    var family: String?

    var themeFamily: ThemeFamily { family.flatMap(ThemeFamily.init) ?? Palette.defaultFamily }

    /// The entry for the given day, or nil when the snapshot does not reach that far.
    func day(for date: Date, calendar: Calendar = .current) -> Day? {
        let key = Self.dayKey(date, calendar: calendar)
        return days.first { $0.day == key }
    }

    /// Studied days as offsets from `date` (0 = that day, -1 = the day before), the form `StudyCalendar` uses.
    func studiedOffsets(relativeTo date: Date, calendar: Calendar = .current) -> Set<Int> {
        let start = calendar.startOfDay(for: date)
        var out: Set<Int> = []
        for key in studied {
            guard let d = Self.parseDay(key, calendar: calendar) else { continue }
            if let n = calendar.dateComponents([.day], from: start, to: d).day, n <= 0, n > -35 { out.insert(n) }
        }
        return out
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseDay(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) -> ReachSnapshot? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let s = try? d.decode(ReachSnapshot.self, from: data), s.version == version else { return nil }
        return s
    }
}

/// Where the snapshot lives: the App Group container shared by app and widget.
enum ReachShared {
    /// Must match `com.apple.security.application-groups` in both entitlements files (project.yml: KARTEI_APP_GROUP).
    static let appGroup = "group.pro.geist.bergmoench.beta"
    static let fileName = "reach-snapshot.json"
    static let widgetKind = "KarteiToday"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func snapshotURL(in folder: URL? = containerURL) -> URL? {
        folder?.appendingPathComponent(fileName)
    }

    static func read(from url: URL? = snapshotURL()) -> ReachSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return ReachSnapshot.decode(data)
    }

    @discardableResult
    static func write(_ snapshot: ReachSnapshot, to url: URL? = snapshotURL()) -> Bool {
        guard let url, let data = try? snapshot.encoded() else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

// MARK: - Widget visuals, kept apart from the app's Theme.swift so the widget builds alone. The widget follows the
// system's light/dark with the family the app wrote into the snapshot.

struct WidgetInk {
    let bg, rule, text, display, muted, accentRule: Color

    init(_ family: ThemeFamily, dark: Bool) {
        let p = Palette.of(family, dark: dark)
        bg = Color(themeHex: p.bg); rule = Color(themeHex: p.rule); text = Color(themeHex: p.text)
        display = Color(themeHex: p.display); muted = Color(themeHex: p.muted); accentRule = Color(themeHex: p.accentRule)
    }
}

enum WidgetType {
    /// Registers the bundled variable fonts for this process. Returns false when they are missing, and the
    /// widget then falls back to the system font (SF, heavy/ultralight) with the same sizes.
    @discardableResult
    static func register(bundle: Bundle = .main) -> Bool {
        var ok = true
        // Courier Prime (GEIST data) is not used by the widget.
        for name in ["BricolageGrotesque", "DMSans", "Nunito", "NotoSerif"] {
            if let url = bundle.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            } else { ok = false }
        }
        return ok
    }

    private static func make(_ family: String, _ size: CGFloat, _ weight: CGFloat, fallback: Font.Weight) -> Font {
        BundledFonts.font(family, size: size, weight: weight).map { Font($0) } ?? .system(size: size, weight: fallback)
    }

    static func display(_ size: CGFloat, heavy: Bool, family: ThemeFamily = Palette.defaultFamily) -> Font {
        make(family.fonts.display, size, heavy ? 800 : 200, fallback: heavy ? .heavy : .ultraLight)
    }

    static func body(_ size: CGFloat, _ weight: CGFloat = 400, family: ThemeFamily = Palette.defaultFamily) -> Font {
        make(family.fonts.body, size, weight, fallback: weight >= 600 ? .bold : weight >= 500 ? .medium : .regular)
    }
}

/// Same grid as the home screen's StudyCalendar: five weeks, Monday first, this week at the bottom, no streak.
struct WidgetCalendar: View {
    let studied: Set<Int>
    let today: Date
    var family: ThemeFamily = Palette.defaultFamily
    @Environment(\.colorScheme) private var scheme
    private var ink: WidgetInk { WidgetInk(family, dark: scheme == .dark) }
    var cell: CGFloat = 12
    var showLetters = true

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let weekday = (cal.component(.weekday, from: cal.startOfDay(for: today)) + 5) % 7
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            if showLetters {
                GridRow {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                        Text(letter).font(WidgetType.body(9, 500, family: family)).foregroundStyle(ink.muted).frame(width: cell)
                    }
                }
            }
            ForEach(0..<5, id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { day in square((week - 4) * 7 + day - weekday) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Studied on \(studied.count) of the last 35 days")
    }

    @ViewBuilder private func square(_ offset: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1)
        if offset > 0 {
            shape.strokeBorder(ink.rule, lineWidth: 1).frame(width: cell, height: cell).opacity(0.45)
        } else if offset == 0 {
            shape.fill(studied.contains(0) ? ink.text : .clear).overlay(shape.strokeBorder(ink.accentRule, lineWidth: 2)).frame(width: cell, height: cell)
        } else if studied.contains(offset) {
            shape.fill(ink.text).frame(width: cell, height: cell)
        } else {
            shape.strokeBorder(ink.rule, lineWidth: 1).frame(width: cell, height: cell)
        }
    }
}

/// The widget's content. `snapshot` nil means the app has not written one yet.
struct ReachWidgetContent: View {
    enum Size { case small, medium }

    let snapshot: ReachSnapshot?
    let date: Date
    let size: Size
    @Environment(\.colorScheme) private var scheme

    private var family: ThemeFamily { snapshot?.themeFamily ?? Palette.defaultFamily }
    private var ink: WidgetInk { WidgetInk(family, dark: scheme == .dark) }

    var body: some View {
        let day = snapshot?.day(for: date)
        let studied = snapshot?.studiedOffsets(relativeTo: date) ?? []
        Group {
            switch size {
            case .small:
                VStack(alignment: .leading, spacing: 0) {
                    numeral(day, big: 44)
                    Spacer(minLength: 6)
                    WidgetCalendar(studied: studied, today: date, family: family, cell: 11, showLetters: false)
                }
            case .medium:
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        numeral(day, big: 64)
                        Text(caption(day)).font(WidgetType.body(12, family: family)).foregroundStyle(ink.muted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        WidgetCalendar(studied: studied, today: date, family: family, cell: 12)
                        Text("\(studied.count) \(studied.count == 1 ? "day" : "days") in 5 weeks").font(WidgetType.body(11, family: family)).foregroundStyle(ink.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size == .medium ? .leading : .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func numeral(_ day: ReachSnapshot.Day?, big: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(day.map { "\($0.minutes)" } ?? "–").font(WidgetType.display(big, heavy: true, family: family)).tracking(-2).lineLimit(1).minimumScaleFactor(0.5)
            Text("min").font(WidgetType.display(big * 0.48, heavy: false, family: family)).lineLimit(1)
        }
        .foregroundStyle(ink.display)
        .accessibilityLabel(day.map { "\($0.minutes) minutes of cards today" } ?? "Open Bergmönch to see today's cards")
    }

    private func caption(_ day: ReachSnapshot.Day?) -> String {
        guard let day else { return "Open Bergmönch once to fill this in." }
        if day.cards == 0 { return "Nothing due today." }
        return "today, about \(day.cards) \(day.cards == 1 ? "card" : "cards")"
    }
}

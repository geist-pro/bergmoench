// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

// Hand-drawn charts in the mockups' style: 2 pt lines, hairline axis, dashed target, accent end dot.
// Each chart carries a text summary for VoiceOver and a hover/drag readout.

private let chartLabel = Type.body(11, 500)

/// Index of the nearest of `count` evenly spaced slots to an x position.
private func slot(_ x: CGFloat, width: CGFloat, count: Int) -> Int {
    guard count > 1, width > 0 else { return 0 }
    return min(count - 1, max(0, Int((x / width * CGFloat(count - 1)).rounded())))
}

/// Readout bubble placed above a chart.
private struct Readout: View {
    let text: String
    var body: some View {
        Text(text).font(Type.body(12, 500)).monospacedDigit().foregroundStyle(Ink.text)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Ink.surface2).clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// Hover (Mac) or drag (touch) picks a slot.
private struct Scrub: ViewModifier {
    let count: Int
    @Binding var selected: Int?
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { selected = slot(p.x, width: geo.size.width, count: count) } else { selected = nil }
                    }
                    // Simultaneous, so a finger moving over the chart still scrolls the page on iPhone.
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .onChanged { selected = slot($0.location.x, width: geo.size.width, count: count) }
                        .onEnded { _ in selected = nil })
            }
        }
    }
}

/// Daily true retention for the last 30 days against the target.
struct RetentionChart: View {
    let days: [StatsMath.Day]
    let target: Double
    /// Days with fewer answers than this are left out of the line (too noisy to read).
    var minimum = 5
    @State private var selected: Int?

    private var points: [(Int, Double)] { days.enumerated().filter { $0.element.total >= minimum }.map { ($0.offset, $0.element.rate) } }
    private var low: Double { max(0, min(points.map(\.1).min() ?? target, target) - 0.08) }

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let h = size.height - 2, w = size.width
                func y(_ v: Double) -> CGFloat { h - CGFloat((v - low) / max(0.01, 1 - low)) * (h - 8) }
                func x(_ i: Int) -> CGFloat { days.count > 1 ? CGFloat(i) / CGFloat(days.count - 1) * w : w / 2 }
                var axis = Path(); axis.move(to: CGPoint(x: 0, y: size.height - 0.5)); axis.addLine(to: CGPoint(x: w, y: size.height - 0.5))
                ctx.stroke(axis, with: .color(Ink.rule), lineWidth: 1)
                var t = Path(); t.move(to: CGPoint(x: 0, y: y(target))); t.addLine(to: CGPoint(x: w, y: y(target)))
                ctx.stroke(t, with: .color(Ink.muted), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ctx.draw(Text("target \(Int((target * 100).rounded()))%").font(chartLabel).foregroundColor(Ink.muted),
                         at: CGPoint(x: 0, y: y(target) - 4), anchor: .bottomLeading)
                guard !points.isEmpty else { return }
                var line = Path()
                for (n, p) in points.enumerated() {
                    let pt = CGPoint(x: x(p.0), y: y(p.1))
                    if n == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                ctx.stroke(line, with: .color(Ink.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    let c = CGPoint(x: x(last.0), y: y(last.1))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Ink.bg))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Ink.accentRule))
                }
                if let s = selected {
                    var m = Path(); m.move(to: CGPoint(x: x(s), y: 0)); m.addLine(to: CGPoint(x: x(s), y: h))
                    ctx.stroke(m, with: .color(Ink.rule), lineWidth: 1)
                }
            }
            .frame(height: 100)
            .modifier(Scrub(count: days.count, selected: $selected))
            .overlay(alignment: .top) { if let s = selected, days.indices.contains(s) { Readout(text: readout(days[s])) } }
            HStack {
                Text(dateLabel(days.first?.offset ?? -29)).font(chartLabel).foregroundStyle(Ink.muted)
                Spacer()
                Text("today").font(chartLabel).foregroundStyle(Ink.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily retention, last 30 days")
        .accessibilityValue(summary)
    }

    private func readout(_ d: StatsMath.Day) -> String {
        let when = d.offset == 0 ? "Today" : dateLabel(d.offset)
        return d.total == 0 ? "\(when): no reviews" : "\(when): \(Int((d.rate * 100).rounded()))% of \(d.total)"
    }

    var summary: String {
        guard !points.isEmpty else { return "Not enough reviews yet to draw a line." }
        let rates = points.map(\.1)
        let above = rates.filter { $0 >= target }.count
        return "\(points.count) days drawn. Lowest \(Int(((rates.min() ?? 0) * 100).rounded()))%, highest \(Int(((rates.max() ?? 0) * 100).rounded()))%. At or above the target on \(above) of them."
    }
}

func dateLabel(_ offset: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate("d MMM")
    return f.string(from: d)
}

func weekdayLabel(_ offset: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.dateFormat = "EEE"
    return f.string(from: d)
}

/// Minutes a day for the next 14 days.
struct ForecastChart: View {
    let days: [StatsMath.ForecastDay]
    @State private var selected: Int?

    var body: some View {
        let top = max(1, days.map(\.minutes).max() ?? 1)
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let n = max(1, days.count)
                let gap: CGFloat = 2, slotW = size.width / CGFloat(n), barW = min(24, slotW - gap)
                for (i, d) in days.enumerated() {
                    let h = d.minutes == 0 ? 1 : max(3, CGFloat(d.minutes) / CGFloat(top) * (size.height - 2))
                    let rect = CGRect(x: CGFloat(i) * slotW + (slotW - barW) / 2, y: size.height - h, width: barW, height: h)
                    let colour = i == selected ? Ink.accentRule : (isWeekend(d.offset) ? Ink.muted : Ink.text)
                    ctx.fill(Path(roundedRect: rect, cornerSize: CGSize(width: min(2, barW / 4), height: min(2, barW / 4))), with: .color(colour))
                }
                var axis = Path(); axis.move(to: CGPoint(x: 0, y: size.height + 0.5)); axis.addLine(to: CGPoint(x: size.width, y: size.height + 0.5))
                ctx.stroke(axis, with: .color(Ink.rule), lineWidth: 1)
            }
            .frame(height: 60)
            .modifier(Scrub(count: days.count, selected: $selected))
            .overlay(alignment: .top) {
                if let s = selected, days.indices.contains(s) {
                    Readout(text: "\(s == 0 ? "Today" : weekdayLabel(days[s].offset) + " " + dateLabel(days[s].offset)): \(days[s].minutes) min, \(days[s].cards) cards")
                }
            }
            GeometryReader { geo in
                let slotW = geo.size.width / CGFloat(max(1, days.count))
                ForEach(labelled, id: \.self) { i in
                    Text(i == 0 ? "Today" : weekdayLabel(days[i].offset)).font(chartLabel).foregroundStyle(Ink.muted)
                        .fixedSize()
                        .position(x: min(max(slotW * (CGFloat(i) + 0.5), 16), geo.size.width - 12), y: 7)
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes a day for the next 14 days")
        .accessibilityValue(days.map { "\($0.offset == 0 ? "today" : weekdayLabel($0.offset)) \($0.minutes)" }.joined(separator: ", "))
    }

    /// Today, each Monday, and the last day.
    private var labelled: [Int] {
        var out = [0]
        for (i, d) in days.enumerated() where i > 1 && i < days.count - 2 && Calendar.current.component(.weekday, from: date(d.offset)) == 2 { out.append(i) }
        if days.count > 3 { out.append(days.count - 1) }
        return out
    }

    private func date(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now }
    private func isWeekend(_ offset: Int) -> Bool { Calendar.current.isDateInWeekend(date(offset)) }
}

/// Proportions of card states in one bar with 2 pt gaps, with a legend of counts underneath.
struct StateBar: View {
    struct Part: Identifiable { let id: String; let count: Int; let colour: Color }
    let parts: [Part]

    var body: some View {
        let total = max(1, parts.reduce(0) { $0 + $1.count })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let shown = parts.filter { $0.count > 0 }
                let free = geo.size.width - CGFloat(max(0, shown.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(shown) { p in
                        Rectangle().fill(p.colour).frame(width: max(3, free * CGFloat(p.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 8) {
                ForEach(parts) { p in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(grouped(p.count)).font(Type.body(15, 700)).monospacedDigit().foregroundStyle(Ink.text)
                        HStack(spacing: 6) {
                            Rectangle().fill(p.colour).frame(width: 10, height: 10)
                            Text(p.id).font(Type.body(13)).foregroundStyle(Ink.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Minutes a day against desired retention, with the current choice marked (pace.html).
struct WorkloadChart: View {
    let minutes: (Float) -> Double
    let current: Float
    let range: ClosedRange<Float>

    var body: some View {
        let samples = stride(from: range.lowerBound, through: range.upperBound + 0.0001, by: 0.01).map { ($0, minutes($0)) }
        let top = max(1, samples.map(\.1).max() ?? 1)
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let h = size.height, w = size.width
                func x(_ r: Float) -> CGFloat { CGFloat((r - range.lowerBound) / (range.upperBound - range.lowerBound)) * w }
                func y(_ m: Double) -> CGFloat { h - 1 - CGFloat(m / top) * (h - 14) }
                var curve = Path()
                for (i, s) in samples.enumerated() {
                    let p = CGPoint(x: x(s.0), y: y(s.1))
                    if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
                }
                var area = curve
                area.addLine(to: CGPoint(x: w, y: h)); area.addLine(to: CGPoint(x: 0, y: h)); area.closeSubpath()
                ctx.fill(area, with: .color(Ink.surface))
                ctx.stroke(curve, with: .color(Ink.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                var axis = Path(); axis.move(to: CGPoint(x: 0, y: h - 0.5)); axis.addLine(to: CGPoint(x: w, y: h - 0.5))
                ctx.stroke(axis, with: .color(Ink.rule), lineWidth: 1)
                let cm = minutes(current), cx = x(current), cy = y(cm)
                var mark = Path(); mark.move(to: CGPoint(x: cx, y: cy)); mark.addLine(to: CGPoint(x: cx, y: h))
                ctx.stroke(mark, with: .color(Ink.accentRule), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 6, y: cy - 6, width: 12, height: 12)), with: .color(Ink.bg))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)), with: .color(Ink.accentRule))
                if let first = samples.first {
                    ctx.draw(Text("\(Int(first.1.rounded())) min").font(chartLabel).foregroundColor(Ink.muted), at: CGPoint(x: 0, y: y(first.1) - 6), anchor: .bottomLeading)
                }
                if let last = samples.last {
                    ctx.draw(Text("\(Int(last.1.rounded())) min a day").font(chartLabel).foregroundColor(Ink.muted), at: CGPoint(x: w - 8, y: max(10, y(last.1))), anchor: .trailing)
                }
            }
            .frame(height: 96)
            HStack {
                Text("\(Int((range.lowerBound * 100).rounded()))%").font(chartLabel)
                Spacer()
                Text("\(Int((range.upperBound * 100).rounded()))%").font(chartLabel)
            }
            .foregroundStyle(Ink.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes a day against how much should stick")
        .accessibilityValue("\(Int(minutes(range.lowerBound).rounded())) minutes at \(Int(range.lowerBound * 100)) percent, \(Int(minutes(current).rounded())) at your \(Int((current * 100).rounded())) percent, \(Int(minutes(range.upperBound).rounded())) at \(Int(range.upperBound * 100)) percent.")
    }
}

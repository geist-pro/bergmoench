// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Arithmetic for the card info screen.
enum CardInfoMath {
    /// FSRS forgetting curve: chance of recall `days` after a review with stability `stability` (days).
    static func recall(days: Double, stability: Double, decay: Double) -> Double {
        guard stability > 0 else { return 0 }
        let factor = pow(0.9, -1 / decay) - 1
        return pow(1 + factor * max(0, days) / stability, -decay)
    }

    /// Name of an answer as Kartei shows it. Again is "Forgot" (F3: Forgot is the only fail).
    static func answerName(button: UInt32, kind: Anki_Stats_RevlogEntry.ReviewKind) -> String {
        switch kind {
        case .manual: return "Rescheduled"
        case .rescheduled: return "Rescheduled"
        default: break
        }
        switch button {
        case 1: return "Forgot"
        case 2: return "Hard"
        case 3: return "Good"
        case 4: return "Easy"
        default: return "Rescheduled"
        }
    }

    struct CurvePoint: Equatable { var t: Double; var r: Double; var miss = false }

    /// The sawtooth "chance of recalling it" line: after each review recall starts at 100 % and decays with that
    /// review's stability; at the next review it drops to the curve value (red when the answer was Forgot).
    /// `entries` oldest first: (time in seconds, button, stability after the review). Times in the result are days since the first.
    static func curve(_ entries: [(time: Int64, button: UInt32, stability: Double?)], now: Int64, decay: Double, samples: Int = 16) -> [CurvePoint] {
        // Start at the first review with a memory state (earlier ones may be outside FSRS's history).
        let rated = entries.filter { $0.button > 0 }
        guard let start = rated.firstIndex(where: { ($0.stability ?? 0) > 0 }) else { return [] }
        let reviews = Array(rated[start...])
        let first = reviews[0]
        var out: [CurvePoint] = []
        func day(_ t: Int64) -> Double { Double(t - first.time) / 86_400 }
        for (i, e) in reviews.enumerated() {
            guard let s = e.stability, s > 0 else { continue }
            let start = day(e.time)
            let end = i + 1 < reviews.count ? day(reviews[i + 1].time) : day(now)
            out.append(CurvePoint(t: start, r: 1))
            for k in 1...samples {
                let t = start + (end - start) * Double(k) / Double(samples)
                let last = k == samples
                out.append(CurvePoint(t: t, r: recall(days: t - start, stability: s, decay: decay),
                                      miss: last && i + 1 < reviews.count && reviews[i + 1].button == 1))
            }
        }
        return out
    }

    /// FSRS-6 cards store their own decay; older parameter sets use 0.5.
    static func decay(card: Anki_Cards_Card?, params: [Float]) -> Double {
        if let card, card.hasDecay, card.decay > 0 { return Double(card.decay) }
        return Workload.decay(params)
    }
}

/// Card info (info.html): FSRS memory state, recall over time, and the full review log.
struct CardInfoView: View {
    let backend: Backend?
    let cardID: Int64
    let model: BrowseModel
    let close: () -> Void

    @State private var stats: Anki_Stats_CardStatsResponse?
    @State private var card: Anki_Cards_Card?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScreenNav(title: "Card info", back: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let stats {
                        content(stats)
                    } else if let error {
                        Meta("Could not read this card: \(error)")
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .background(Ink.bg)
        .task(id: cardID) { load() }
    }

    private func load() {
        guard let backend else { return }
        let cid = cardID
        Task.detached(priority: .userInitiated) {
            var id = Anki_Cards_CardId()
            id.cid = cid
            do {
                let s: Anki_Stats_CardStatsResponse = try backend.call(StatsMethods.cardStats, id)
                let c: Anki_Cards_Card = try backend.call(CardsMethods.getCard, id)
                await MainActor.run { stats = s; card = c }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }

    @ViewBuilder
    private func content(_ s: Anki_Stats_CardStatsResponse) -> some View {
        let row = model.rows[cardID]
        Text(row?.question ?? "").font(Type.display(22, heavy: false)).foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            .accessibilityAddTraits(.isHeader)

        HStack(alignment: .top, spacing: 8) {
            kv(s.hasMemoryState ? spanText(seconds: Double(s.memoryState.stability) * 86_400) : "–", "Stability",
               hint: "How long until recall drops to 90%")
            kv(s.hasFsrsRetrievability ? "\(Int((s.fsrsRetrievability * 100).rounded()))%" : "–", "Recall now",
               hint: "Estimated chance you would remember it right now")
            kv(s.hasMemoryState ? String(format: "%.1f", s.memoryState.difficulty) : "–", "Difficulty",
               hint: "FSRS difficulty from 1 to 10")
            kv("\(s.lapses)", "Lapses", hint: "Times forgotten after it was learnt")
        }
        .padding(.top, 14)
        if !s.fsrsEnabled { Meta("FSRS is off, so stability and recall are not estimated. Turn it on under Settings, Pace.").padding(.top, 6) }

        let points = curvePoints(s)
        if points.count > 2, (points.last?.t ?? 0) >= 1 {
            Caption("Chance of recalling it, since you first saw it").padding(.top, 20).padding(.bottom, 8)
            RecallChart(points: points, target: Double(s.desiredRetention > 0 ? s.desiredRetention : 0.9),
                        start: s.revlog.reversed().first { $0.buttonChosen > 0 && $0.hasMemoryState }?.time ?? s.added)
        }

        log(s.revlog).padding(.top, 20)

        Meta(footer(s)).padding(.top, 12)
        actions.padding(.top, 16)
    }

    private func kv(_ value: String, _ label: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Type.body(18, 700)).monospacedDigit().foregroundStyle(Ink.text)
            Text(label).font(Type.body(13)).foregroundStyle(Ink.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint(hint)
    }

    private func curvePoints(_ s: Anki_Stats_CardStatsResponse) -> [CardInfoMath.CurvePoint] {
        let entries = s.revlog.reversed().map { e in (time: e.time, button: e.buttonChosen, stability: e.hasMemoryState ? Double(e.memoryState.stability) : nil) }
        return CardInfoMath.curve(entries, now: Int64(Date().timeIntervalSince1970), decay: CardInfoMath.decay(card: card, params: s.fsrsParams))
    }

    private func log(_ entries: [Anki_Stats_CardStatsResponse.StatsRevlogEntry]) -> some View {
        VStack(spacing: 0) {
            logRow("Date", "Answer", "Next in", "Took", header: true)
            if entries.isEmpty {
                Meta("Not reviewed yet.").padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                let name = CardInfoMath.answerName(button: e.buttonChosen, kind: e.reviewKind)
                logRow(dayText(e.time), name, e.interval == 0 ? "–" : spanText(seconds: Double(e.interval)),
                       e.takenSecs > 0 ? "\(Int(e.takenSecs.rounded())) s" : "–", forgot: e.buttonChosen == 1)
            }
        }
    }

    private func logRow(_ a: String, _ b: String, _ c: String, _ d: String, header: Bool = false, forgot: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(a).frame(width: 64, alignment: .leading)
            HStack(spacing: 6) {
                if forgot { Rectangle().fill(Ink.forgot).frame(width: 8, height: 8) }
                Text(b).font(header ? Type.body(12, 500) : Type.body(14, 700))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(c).frame(width: 64, alignment: .trailing).foregroundStyle(header ? Ink.muted : Ink.muted)
            Text(d).frame(width: 48, alignment: .trailing).foregroundStyle(Ink.muted)
        }
        .font(header ? Type.body(12, 500) : Type.body(14))
        .monospacedDigit()
        .foregroundStyle(header ? Ink.muted : Ink.text)
        .frame(minHeight: header ? 26 : 34)
        .overlay(alignment: .bottom) { Rectangle().fill(header ? Ink.accentRule : Ink.rule).frame(height: header ? 2 : 1) }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(header)
    }

    private func dayText(_ secs: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        let d = Date(timeIntervalSince1970: TimeInterval(secs))
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(d, equalTo: .now, toGranularity: .year) ? "d MMM" : "d MMM yy")
        return f.string(from: d)
    }

    private func footer(_ s: Anki_Stats_CardStatsResponse) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        var parts = ["\(s.notetype) note, \(s.cardType).", "Added \(f.string(from: Date(timeIntervalSince1970: TimeInterval(s.added))))."]
        if let due = model.rows[cardID]?.status.due { parts.append("Due \(due).") }
        if !s.preset.isEmpty { parts.append("Preset \(s.preset).") }
        return parts.joined(separator: " ")
    }

    private var actions: some View {
        let row = model.rows[cardID]
        return VStack(alignment: .leading, spacing: 8) {
            Caption("Flag")
            FlagPicker(flag: row?.flag ?? 0) { model.setFlag($0, on: cardID) }
            Button {
                model.setSuspended(!(row?.status.suspended ?? false), [cardID])
            } label: {
                Text(row?.status.suspended == true ? "Unsuspend" : "Suspend").font(Type.body(15, 500)).foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityHint("A suspended card stays out of reviews until you unsuspend it.")
        }
    }
}

/// Sawtooth recall chart with misses in red and today's value as the accent dot.
struct RecallChart: View {
    let points: [CardInfoMath.CurvePoint]
    let target: Double
    let start: Int64

    var body: some View {
        let span = max(1, points.map(\.t).max() ?? 1)
        let low = max(0, min(points.map(\.r).min() ?? 0.5, target) - 0.05)
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let h = size.height - 2, w = size.width
                func x(_ t: Double) -> CGFloat { CGFloat(t / span) * w }
                func y(_ r: Double) -> CGFloat { 4 + (1 - CGFloat((r - low) / max(0.01, 1 - low))) * (h - 8) }
                var t = Path(); t.move(to: CGPoint(x: 0, y: y(target))); t.addLine(to: CGPoint(x: w, y: y(target)))
                ctx.stroke(t, with: .color(Ink.muted), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ctx.draw(Text("\(Int((target * 100).rounded()))%").font(Type.body(11, 500)).foregroundColor(Ink.muted), at: CGPoint(x: w * 0.18, y: y(target) + 4), anchor: .top)
                var line = Path()
                for (i, p) in points.enumerated() {
                    let pt = CGPoint(x: x(p.t), y: y(p.r))
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                ctx.stroke(line, with: .color(Ink.text), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for p in points where p.miss {
                    let c = CGPoint(x: x(p.t), y: y(p.r))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Ink.forgot))
                }
                if let last = points.last {
                    let c = CGPoint(x: x(last.t), y: y(last.r))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Ink.accentRule))
                }
                var axis = Path(); axis.move(to: CGPoint(x: 0, y: size.height - 0.5)); axis.addLine(to: CGPoint(x: w, y: size.height - 0.5))
                ctx.stroke(axis, with: .color(Ink.rule), lineWidth: 1)
            }
            .frame(height: 90)
            HStack {
                Text(startLabel).font(Type.body(11, 500))
                Spacer()
                Text("today").font(Type.body(11, 500))
            }
            .foregroundStyle(Ink.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated recall over time")
        .accessibilityValue("Now \(Int(((points.last?.r ?? 0) * 100).rounded())) percent. Forgotten \(points.filter(\.miss).count) times.")
    }

    private var startLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(start)))
    }
}

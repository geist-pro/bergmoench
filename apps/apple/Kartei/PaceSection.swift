// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Settings section header, shared by Kartei's own settings sections.
struct SettingsHeader: View {
    let title: String
    var body: some View {
        Text(title).font(Type.display(22, heavy: true)).foregroundStyle(Ink.text)
            .padding(.top, 24).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Pace (pace.html): Anki's deck options, led by the one setting that matters most (F2: desired retention),
/// with the workload each choice costs in minutes a day.
struct PaceSection: View {
    let store: DeckStore
    @State private var pace = PaceStore()
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Pace")
            if pace.loaded {
                presetLine
                retention
                newCards
                lighterDays
                fsrsRow
                ListLine(title: "Advanced", detail: "Learning steps, leech limit, FSRS parameters") { advanced = true }
            } else if let e = pace.error {
                Meta(e).padding(.vertical, 8)
            } else {
                ProgressView().controlSize(.small).padding(.vertical, 12)
            }
            if pace.loaded, let e = pace.error { Meta("Not saved: \(e)").padding(.top, 6) }
        }
        .onAppear { pace.attach(store.backend, secondsPerCard: store.secondsPerCard) }
        .onChange(of: store.backend == nil) { pace.attach(store.backend, secondsPerCard: store.secondsPerCard) }
        .sheet(isPresented: $advanced) { PaceAdvanced(pace: pace) { advanced = false } }
    }

    // MARK: preset

    @ViewBuilder
    private var presetLine: some View {
        let p = pace.preset
        let n = p?.decks.count ?? 0
        let detail = n == 1 ? "Used by 1 deck." : "Shared by \(n) decks. Changes apply to all of them."
        if pace.presets.count > 1 {
            Menu {
                ForEach(pace.presets) { preset in
                    Button("\(preset.name) (\(preset.decks.count) deck\(preset.decks.count == 1 ? "" : "s"))") { pace.select(preset.id) }
                }
            } label: {
                ListLine(title: "Preset: \(p?.name ?? "")", detail: detail, value: nil, action: {})
                    .allowsHitTesting(false)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel("Preset \(p?.name ?? ""). \(detail)")
            .accessibilityHint("Choose which preset to change")
        } else {
            ListLine(title: "Preset: \(p?.name ?? "")", detail: detail)
        }
    }

    // MARK: desired retention

    private var retentionBinding: Binding<Double> {
        Binding(get: { Double(pace.retention) }, set: { pace.config.config.desiredRetention = Float(($0 * 100).rounded() / 100) })
    }

    private var retention: some View {
        let r = pace.retention
        let mins = pace.minutes(at: r)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How much should stick").font(Type.body(15, 700)).foregroundStyle(Ink.text)
                Spacer()
                Text("default \(Int(PaceDefaults.desiredRetention * 100))%").font(Type.body(13)).foregroundStyle(Ink.muted)
            }
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int((r * 100).rounded()))").font(Type.display(64, heavy: true)).monospacedDigit()
                    Text("%").font(Type.display(34, heavy: false))
                }
                .foregroundStyle(Ink.display)
                .accessibilityHidden(true)
                Spacer()
                (Text("costs about ") + Text("\(Int(mins.rounded())) min a day").foregroundColor(Ink.text).bold()
                    + Text(pace.simulated ? "\nover the next year, simulated" : "\nestimated from your due cards"))
                    .font(Type.body(13)).foregroundStyle(Ink.muted).multilineTextAlignment(.trailing)
            }
            WorkloadChart(minutes: { pace.minutes(at: $0) }, current: r, range: PaceDefaults.minRetention...PaceDefaults.maxRetention)
            Slider(value: retentionBinding, in: Double(PaceDefaults.minRetention)...Double(PaceDefaults.maxRetention), step: 0.01)
            .tint(Ink.text)
            .frame(minHeight: 44)
            .accessibilityLabel("How much should stick")
            .accessibilityValue("\(Int((r * 100).rounded())) percent, about \(Int(mins.rounded())) minutes a day")
            .onChange(of: pace.config.config.desiredRetention) { pace.save() }
            Meta(retentionNote(r))
                .foregroundStyle(r > PaceDefaults.warnAbove ? Ink.learning : Ink.muted)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func retentionNote(_ r: Float) -> String {
        if r > PaceDefaults.warnAbove {
            let ratio = pace.minutes(at: r) / max(0.1, pace.minutes(at: 0.9))
            return String(format: "Above 95%% the workload rises steeply: this costs about %.1f× what 90%% does, for a few more cards remembered.", ratio)
        }
        if r < 0.8 { return "Below 80% you will forget one card in five or more; reviews feel harder." }
        return "The share of cards you should still remember when they come back. No single value is best for everyone; 90% is Anki's default."
    }

    // MARK: new cards

    private var newCardsBinding: Binding<Int> {
        Binding(get: { Int(pace.config.config.newPerDay) }, set: { pace.config.config.newPerDay = UInt32($0); pace.save() })
    }

    private var newCards: some View {
        let n = Int(pace.config.config.newPerDay)
        let reviews = Workload.steadyReviews(newPerDay: n, factor: pace.workloadFactor(at: pace.retention))
        let mins = Workload.minutes(reviews: Double(reviews), secondsPerCard: pace.secondsPerCard)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New cards a day").font(Type.body(15, 700)).foregroundStyle(Ink.text)
                Meta(n == 0 ? "No new cards: only reviews." : "\(n) new settles at about \(reviews) reviews a day, \(mins) min.")
                if n == Int(PaceDefaults.newPerDay) { Meta("Bergmönch's default. New cards are what build a backlog.") }
            }
            Spacer()
            CountStepper(label: "New cards a day", value: newCardsBinding, range: 0...200)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rule() }
    }

    // MARK: lighter days

    private var lighterDays: some View {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let values = pace.config.config.easyDaysPercentages.count == 7 ? pace.config.config.easyDaysPercentages : Array(repeating: 1, count: 7)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lighter days").font(Type.body(15, 700)).foregroundStyle(Ink.text)
                Spacer()
                Text("reviews move to the other days").font(Type.body(13)).foregroundStyle(Ink.muted)
            }
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let day = LighterDay.of(values[i])
                    Button {
                        var v = values
                        v[i] = day.next.rawValue
                        pace.config.config.easyDaysPercentages = v
                        pace.save(debounce: false)
                    } label: {
                        VStack(spacing: 0) {
                            Text(String(names[i].prefix(1))).font(Type.body(13, 700))
                            if day != .normal { Text(day.label).font(Type.body(10)).foregroundStyle(Ink.muted) }
                        }
                        .foregroundStyle(day == .least ? Ink.muted : Ink.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(day == .half ? Ink.surface : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, style: StrokeStyle(lineWidth: 1, dash: day == .least ? [3, 3] : [])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(names[i])
                    .accessibilityValue(day.spoken)
                    .accessibilityHint("Changes between normal, half and as few as possible")
                }
            }
            Meta("Tap a day for half or as few reviews as possible. Total reviews stay the same; spreading the load is what keeps it manageable.")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rule() }
    }

    // MARK: FSRS

    private var fsrsRow: some View {
        Toggle(isOn: Binding(get: { pace.fsrs }, set: { pace.fsrs = $0; pace.save(debounce: false) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FSRS scheduler").font(Type.body(16, 500)).foregroundStyle(Ink.text)
                Meta(pace.fsrs ? "On by default in Bergmönch. In the open benchmark FSRS predicts forgetting better than Anki's older SM-2 for 99.6% of people."
                               : "Off: Anki's older SM-2 schedules the cards and the workload is only an estimate.")
            }
        }
        .toggleStyle(.switch).tint(Ink.accent)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityHint("Applies to all decks in the collection")
    }
}

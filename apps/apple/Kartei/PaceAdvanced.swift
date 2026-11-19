// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Learning steps as text: "1m 10m", "1d". Anki stores them in minutes.
enum StepsText {
    static func format(_ steps: [Float]) -> String {
        steps.map { m in
            if m >= 1_440, m.truncatingRemainder(dividingBy: 1_440) == 0 { return "\(Int(m / 1_440))d" }
            if m >= 60, m.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(m / 60))h" }
            if m < 1 { return "\(Int((m * 60).rounded()))s" }
            return m == m.rounded() ? "\(Int(m))m" : String(format: "%.1fm", m)
        }.joined(separator: " ")
    }

    /// Parse "1m 10m", "1 10", "30s 1h 1d". Nil when any part is not understood; an empty string means no steps.
    static func parse(_ text: String) -> [Float]? {
        var out: [Float] = []
        for raw in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }) {
            var part = String(raw)
            var unit: Float = 1
            if let last = part.last, "smhd".contains(last) {
                unit = ["s": 1 / 60, "m": 1, "h": 60, "d": 1_440][String(last)]!
                part.removeLast()
            }
            guard let v = Float(part), v > 0 else { return nil }
            out.append(v * unit)
        }
        return out
    }

    /// Human wording for the list: "1 min, 10 min".
    static func spoken(_ steps: [Float]) -> String {
        steps.isEmpty ? "none" : steps.map { spanText(seconds: Double($0) * 60) }.joined(separator: ", ")
    }
}

/// Advanced (advanced.html): Anki's deck options under their usual names.
struct PaceAdvanced: View {
    @Bindable var pace: PaceStore
    let done: () -> Void

    @State private var learn = ""
    @State private var relearn = ""
    @State private var learnBad = false
    @State private var relearnBad = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenNav(title: "Advanced", back: done) {
                Button("Done", action: done).buttonStyle(.plain).font(Type.body(15, 700)).foregroundStyle(Ink.text)
                    .frame(minWidth: 44, minHeight: 44).keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Meta("Preset: \(pace.preset?.name ?? ""). These are Anki's deck options under their usual names. The defaults suit most people.")
                        .padding(.vertical, 8)
                    stepsRow("Learning steps", text: $learn, bad: learnBad, defaultText: "1m 10m") { steps in
                        pace.config.config.learnSteps = steps
                    }
                    stepsRow("Relearning steps", text: $relearn, bad: relearnBad, defaultText: "10m") { steps in
                        pace.config.config.relearnSteps = steps
                    }
                    stepper("Maximum interval", detail: "Longest gap between reviews. Anki's default is no real limit.",
                            value: Binding(get: { Int(pace.config.config.maximumReviewInterval) },
                                           set: { pace.config.config.maximumReviewInterval = UInt32($0); pace.save() }),
                            range: 1...36_500, step: maxIntervalStep, format: Self.intervalText)
                    stepper("Leech threshold", detail: "After this many lapses Bergmönch asks you to rewrite, split or suspend the card. Default 8.",
                            value: Binding(get: { Int(pace.config.config.leechThreshold) },
                                           set: { pace.config.config.leechThreshold = UInt32($0); pace.save() }),
                            range: 1...99)
                    Caption("FSRS").padding(.top, 24).padding(.bottom, 4)
                    ListLine(title: pace.config.config.fsrsParams6.isEmpty ? "Default parameters" : "Fitted to your reviews",
                             detail: pace.fitMessage ?? (pace.config.config.fsrsParams6.isEmpty ? "Fit once you have a few hundred reviews." : nil),
                             value: paramsText)
                    Button { pace.fit() } label: {
                        HStack(spacing: 8) {
                            if pace.fitting { ProgressView().controlSize(.small) }
                            Text(pace.fitting ? "Fitting" : "Fit again now").font(Type.body(15, 500))
                        }
                        .foregroundStyle(Ink.text).frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(pace.fitting || !pace.fsrs).padding(.top, 16)
                    .accessibilityHint("Fits the FSRS parameters to this preset's review history")
                    if !pace.fsrs { Meta("FSRS is off. Turn it on under Pace to fit parameters.").padding(.top, 6) }
                    Button("Reset to Bergmönch's defaults") { resetDefaults() }
                        .buttonStyle(.plain).font(Type.body(15, 500)).underline().foregroundStyle(Ink.text)
                        .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 16)
                    Meta("Learning steps 1m 10m, relearning 10m, leech threshold 8, 90% retention, 10 new cards a day. Fitted FSRS parameters stay.")
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(Ink.bg)
        .frame(minWidth: 380, minHeight: 560)
        .onAppear {
            learn = StepsText.format(pace.config.config.learnSteps)
            relearn = StepsText.format(pace.config.config.relearnSteps)
        }
    }

    private var maxIntervalStep: Int {
        let v = Int(pace.config.config.maximumReviewInterval)
        return v > 3_650 ? 365 : v > 365 ? 30 : v > 60 ? 7 : 1
    }

    private var paramsText: String {
        let p = pace.config.config.fsrsParams6
        guard !p.isEmpty else { return "FSRS-6" }
        return p.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ", ") + " …"
    }

    private func stepsRow(_ title: String, text: Binding<String>, bad: Bool, defaultText: String, apply: @escaping ([Float]) -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Type.body(16, 500)).foregroundStyle(Ink.text)
                Text(bad ? "Use minutes, hours or days, like 1m 10m 1d" : "Default \(defaultText)").font(Type.body(13))
                    .foregroundStyle(bad ? Ink.forgot : Ink.muted)
            }
            Spacer()
            TextField(title, text: text)
                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(Type.body(15)).foregroundStyle(Ink.text)
                .frame(maxWidth: 140, minHeight: 44)
                .autocorrectionDisabled()
                .onSubmit { commit(text.wrappedValue, title: title, apply: apply) }
                .onChange(of: text.wrappedValue) { commit(text.wrappedValue, title: title, apply: apply) }
                .accessibilityLabel(title)
        }
        .padding(.vertical, 8).frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func commit(_ text: String, title: String, apply: ([Float]) -> Void) {
        let parsed = StepsText.parse(text)
        let isLearn = title == "Learning steps"
        if isLearn { learnBad = parsed == nil } else { relearnBad = parsed == nil }
        guard let parsed, parsed != (isLearn ? pace.config.config.learnSteps : pace.config.config.relearnSteps) else { return }
        apply(parsed)
        pace.save()
    }

    /// Maximum interval in days, worded: "60 d", "1 y", "100 y".
    static func intervalText(_ days: Int) -> String {
        days >= 365 && days % 365 == 0 ? "\(days / 365) y" : days >= 365 ? String(format: "%.1f y", Double(days) / 365) : "\(days) d"
    }

    private func stepper(_ title: String, detail: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, format: ((Int) -> String)? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Type.body(16, 500)).foregroundStyle(Ink.text)
                Meta(detail)
            }
            Spacer()
            CountStepper(label: title, value: value, range: range, step: step, format: format)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func resetDefaults() {
        var c = pace.config.config
        c.learnSteps = PaceDefaults.learnSteps
        c.relearnSteps = PaceDefaults.relearnSteps
        c.leechThreshold = PaceDefaults.leechThreshold
        c.desiredRetention = PaceDefaults.desiredRetention
        c.newPerDay = PaceDefaults.newPerDay
        c.maximumReviewInterval = PaceDefaults.maximumInterval
        pace.config.config = c
        learn = StepsText.format(c.learnSteps)
        relearn = StepsText.format(c.relearnSteps)
        pace.save(debounce: false)
    }
}

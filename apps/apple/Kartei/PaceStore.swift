// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation

/// Kartei's defaults for deck options. Each one is listed with its evidence in docs/science-defaults.md.
enum PaceDefaults {
    /// Anki's default; workload rises steeply above 90 %, and no value is "optimal" for everyone.
    static let desiredRetention: Float = 0.90
    static let minRetention: Float = 0.70
    static let maxRetention: Float = 0.97
    /// Above this the slider warns that workload rises steeply (Anki warns at the same point).
    static let warnAbove: Float = 0.95
    /// New cards drive the backlog; 10 a day with its workload shown instead of Anki's 20.
    static let newPerDay: UInt32 = 10
    /// Rule of thumb from the science doc: each daily new card settles at about 10 reviews a day.
    static let reviewsPerNewCard = 10.0
    static let learnSteps: [Float] = [1, 10]
    static let relearnSteps: [Float] = [10]
    static let leechThreshold: UInt32 = 8
    /// Anki's default maximum interval (100 years, i.e. no cap).
    static let maximumInterval: UInt32 = 36_500
    /// Seconds per card until there is review history to measure from.
    static let secondsPerCard = 8.0
}

/// Workload arithmetic for the pace screen.
enum Workload {
    /// FSRS-6's default forgetting-curve decay (w20); FSRS-4.5/5 use 0.5.
    static let fsrs6Decay = 0.1542

    /// Decay of a parameter set: w20 for FSRS-6 (21 values), else 0.5; defaults when none are fitted.
    static func decay(_ params: [Float]) -> Double {
        if params.count >= 21 { return Double(params[20]) }
        if params.isEmpty { return fsrs6Decay }
        return 0.5
    }

    /// How long intervals are at retention `r`, relative to 90 %. From the FSRS forgetting curve
    /// R(t) = (1 + f·t/S)^-decay with f = 0.9^(-1/decay) - 1, solved for t.
    static func intervalRatio(_ r: Double, decay: Double = fsrs6Decay) -> Double {
        let r = min(max(r, 0.5), 0.995)
        return (pow(r, -1 / decay) - 1) / (pow(0.9, -1 / decay) - 1)
    }

    /// Steady-state reviews a day from `newPerDay` new cards: about 10 per new card at 90 %, more at higher retention.
    static func steadyReviews(newPerDay: Int, retention: Double = 0.9, decay: Double = fsrs6Decay) -> Int {
        steadyReviews(newPerDay: newPerDay, factor: 1 / intervalRatio(retention, decay: decay))
    }

    /// Same, with the workload factor relative to 90 % given (e.g. from the simulator).
    static func steadyReviews(newPerDay: Int, factor: Double) -> Int {
        Int((Double(newPerDay) * PaceDefaults.reviewsPerNewCard * factor).rounded())
    }

    static func minutes(reviews: Double, secondsPerCard: Double) -> Int {
        reviews <= 0 ? 0 : max(1, Int((reviews * secondsPerCard / 60).rounded()))
    }

    /// Fallback estimate when the simulator gives nothing usable: today's expected reviews a day (Anki's "daily load",
    /// the sum of 1/interval over cards) plus the steady state of the new-card limit, scaled by the interval ratio.
    static func estimate(dailyLoad: Double, newPerDay: Int, retention: Double, secondsPerCard: Double, decay: Double = fsrs6Decay) -> Double {
        let at90 = dailyLoad + Double(newPerDay) * PaceDefaults.reviewsPerNewCard
        return at90 / intervalRatio(retention, decay: decay) * secondsPerCard / 60
    }

    /// The simulator returns total seconds over the simulated days per retention (70…99); turn that into minutes a day.
    static func minutesPerDay(cost: [UInt32: Float], days: Int) -> [Int: Double] {
        guard days > 0 else { return [:] }
        var out: [Int: Double] = [:]
        for (dr, secs) in cost where secs.isFinite && secs >= 0 { out[Int(dr)] = Double(secs) / Double(days) / 60 }
        return out
    }

    /// A simulated curve is usable when it covers the slider range and is not all zero.
    static func usable(_ curve: [Int: Double]) -> Bool {
        (70...97).allSatisfy { curve[$0] != nil } && curve.values.contains { $0 > 0.05 }
    }
}

/// A deck options preset and the decks that use it.
struct PacePreset: Identifiable, Equatable {
    let id: Int64
    var name: String
    var decks: [Int64]
}

/// Lighter days (Anki's Easy Days): share of the normal load per weekday, Monday first.
enum LighterDay: Float, CaseIterable {
    case normal = 1.0, half = 0.5, least = 0.0

    var label: String { switch self { case .normal: "" case .half: "half" case .least: "least" } }
    var spoken: String { switch self { case .normal: "normal" case .half: "half the reviews" case .least: "as few reviews as possible" } }
    var next: LighterDay { switch self { case .normal: .half case .half: .least case .least: .normal } }

    static func of(_ v: Float) -> LighterDay { v >= 0.75 ? .normal : v >= 0.25 ? .half : .least }
}

/// Reads and writes deck options through GetDeckConfigsForUpdate / UpdateDeckConfigs, as Anki's options screen does.
@Observable
final class PaceStore {
    private(set) var presets: [PacePreset] = []
    private(set) var selected: Int64 = 1
    /// The editable preset. Change it, then call `save()`.
    var config = Anki_DeckConfig_DeckConfig()
    var fsrs = true
    private(set) var loaded = false
    private(set) var error: String?
    /// Minutes a day by desired retention (percent), and whether it came from the simulator.
    private(set) var curve: [Int: Double] = [:]
    private(set) var simulated = false
    private(set) var fitting = false
    var fitMessage: String?
    var secondsPerCard = PaceDefaults.secondsPerCard

    @ObservationIgnored private var backend: Backend?
    @ObservationIgnored private var update = Anki_DeckConfig_DeckConfigsForUpdate()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var curveTask: Task<Void, Never>?
    @ObservationIgnored private var dailyLoad = 0.0

    var preset: PacePreset? { presets.first { $0.id == selected } }
    var retention: Float { config.config.desiredRetention > 0 ? config.config.desiredRetention : PaceDefaults.desiredRetention }

    func attach(_ backend: Backend?, secondsPerCard: Double) {
        self.secondsPerCard = secondsPerCard
        guard let backend, self.backend !== backend else { return }
        self.backend = backend
        reload()
    }

    func reload(select id: Int64? = nil) {
        guard let backend else { return }
        let want = id ?? (loaded ? selected : nil)
        Task.detached(priority: .userInitiated) { [self] in
            do {
                let presets = try Self.presets(backend)
                let chosen = want.flatMap { w in presets.first { $0.id == w } } ?? presets.max { $0.decks.count < $1.decks.count }
                guard let chosen, let deck = chosen.decks.first else { throw BackendFailure(message: "No decks yet.") }
                let update = try Self.forUpdate(backend, deck: deck)
                let load = Self.dailyLoad(backend, preset: chosen.name)
                await MainActor.run {
                    self.presets = presets
                    self.selected = chosen.id
                    self.update = update
                    self.fsrs = update.fsrs
                    self.config = update.allConfig.first { $0.config.id == chosen.id }?.config ?? update.defaults
                    self.dailyLoad = load
                    self.loaded = true
                    self.error = nil
                    self.refreshCurve()
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }

    func select(_ id: Int64) { reload(select: id) }

    // MARK: workload

    /// Minutes a day at a retention (0…1), from the simulated curve if there is one, else the estimate.
    func minutes(at retention: Float) -> Double {
        let pct = Int((retention * 100).rounded())
        if let m = curve[pct] { return m }
        return Workload.estimate(dailyLoad: dailyLoad, newPerDay: Int(config.config.newPerDay), retention: Double(retention),
                                 secondsPerCard: secondsPerCard, decay: Workload.decay(config.config.fsrsParams6))
    }

    /// Reviews at retention `r` relative to 90 %: from the simulated curve when there is one, else from the forgetting curve.
    func workloadFactor(at r: Float) -> Double {
        if simulated, let at90 = curve[90], at90 > 0, let m = curve[Int((r * 100).rounded())] { return m / at90 }
        return 1 / Workload.intervalRatio(Double(r), decay: Workload.decay(config.config.fsrsParams6))
    }

    func refreshCurve() {
        guard let backend, let preset else { return }
        let request = Self.simulationRequest(config, search: Self.presetSearch(preset.name))
        curveTask?.cancel()
        curveTask = Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let curve = (try? Self.simulate(backend, request)) ?? [:]
            if Task.isCancelled { return }
            await MainActor.run {
                if Workload.usable(curve) { self.curve = curve; self.simulated = true } else { self.curve = [:]; self.simulated = false }
            }
        }
    }

    static let simulatedDays = 365

    static func simulationRequest(_ config: Anki_DeckConfig_DeckConfig, search: String) -> Anki_Scheduler_SimulateFsrsReviewRequest {
        let c = config.config
        var req = Anki_Scheduler_SimulateFsrsReviewRequest()
        req.params = c.fsrsParams6
        req.desiredRetention = c.desiredRetention > 0 ? c.desiredRetention : PaceDefaults.desiredRetention
        req.newLimit = c.newPerDay
        req.reviewLimit = 9999
        req.maxInterval = c.maximumReviewInterval > 0 ? c.maximumReviewInterval : PaceDefaults.maximumInterval
        req.search = search
        req.easyDaysPercentages = c.easyDaysPercentages.count == 7 ? c.easyDaysPercentages : Array(repeating: 1, count: 7)
        req.reviewOrder = c.reviewOrder
        req.historicalRetention = c.historicalRetention > 0 ? c.historicalRetention : 0.9
        req.learningStepCount = UInt32(c.learnSteps.count)
        req.relearningStepCount = UInt32(c.relearnSteps.count)
        req.daysToSimulate = UInt32(simulatedDays)
        return req
    }

    /// Anki's own workload simulation (the one behind its desired-retention help): a year of this preset's cards
    /// at each retention from 70 to 99 %, with the time costs measured from your review log.
    static func simulate(_ backend: Backend, _ req: Anki_Scheduler_SimulateFsrsReviewRequest) throws -> [Int: Double] {
        let resp: Anki_Scheduler_SimulateFsrsWorkloadResponse = try backend.call(SchedulerMethods.simulateFsrsWorkload, req)
        return Workload.minutesPerDay(cost: resp.cost, days: Int(req.daysToSimulate))
    }

    static func presetSearch(_ name: String) -> String {
        "preset:\"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" -is:suspended"
    }

    static func dailyLoad(_ backend: Backend, preset: String) -> Double {
        var req = Anki_Stats_GraphsRequest()
        req.search = presetSearch(preset)
        req.days = 1
        guard let g: Anki_Stats_GraphsResponse = try? backend.call(StatsMethods.graphs, req) else { return 0 }
        return Double(g.futureDue.dailyLoad)
    }

    // MARK: saving

    /// Save the preset (debounced, so dragging the slider writes once).
    func save(debounce: Bool = true) {
        guard let backend, let preset, let deck = preset.decks.first else { return }
        let config = config, fsrs = fsrs, update = update
        saveTask?.cancel()
        saveTask = Task.detached(priority: .userInitiated) { [self] in
            if debounce { try? await Task.sleep(nanoseconds: 500_000_000) }
            if Task.isCancelled { return }
            do {
                try Self.write(backend, config: config, fsrs: fsrs, deck: deck, update: update)
                await MainActor.run { self.error = nil }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
        refreshCurve()
    }

    static func write(_ backend: Backend, config: Anki_DeckConfig_DeckConfig, fsrs: Bool, deck: Int64, update: Anki_DeckConfig_DeckConfigsForUpdate) throws {
        var req = Anki_DeckConfig_UpdateDeckConfigsRequest()
        req.targetDeckID = deck
        req.configs = [config]
        req.mode = .normal
        // Everything else is written back as it was read: UpdateDeckConfigs sets these collection-wide.
        req.cardStateCustomizer = update.cardStateCustomizer
        req.limits = update.currentDeck.limits
        req.newCardsIgnoreReviewLimit = update.newCardsIgnoreReviewLimit
        req.applyAllParentLimits = update.applyAllParentLimits
        req.fsrsHealthCheck = update.fsrsHealthCheck
        req.fsrs = fsrs
        req.fsrsReschedule = false
        let _: Anki_Collection_OpChanges = try backend.call(DeckConfigMethods.updateDeckConfigs, req)
    }

    // MARK: FSRS fit

    /// Fit FSRS parameters to this preset's reviews (Anki's "Optimize"). Keeps the old ones if there are too few reviews.
    func fit() {
        guard let backend, let preset else { return }
        fitting = true
        fitMessage = nil
        let current = config.config.fsrsParams6, relearn = UInt32(config.config.relearnSteps.count)
        let search = config.config.paramSearch.isEmpty ? Self.presetSearch(preset.name) : config.config.paramSearch
        Task.detached(priority: .userInitiated) { [self] in
            var req = Anki_Scheduler_ComputeFsrsParamsRequest()
            req.search = search
            req.currentParams = current
            req.numOfRelearningSteps = relearn
            let result: Result<Anki_Scheduler_ComputeFsrsParamsResponse, Error> = Result { try backend.call(SchedulerMethods.computeFsrsParams, req) }
            await MainActor.run {
                self.fitting = false
                switch result {
                case .success(let r):
                    if r.params.isEmpty || r.params == current {
                        self.fitMessage = r.fsrsItems == 0 ? "No reviews to fit yet. The defaults stay." : "Fitted on \(r.fsrsItems) reviews; the current parameters already fit best."
                    } else {
                        self.config.config.fsrsParams6 = r.params
                        self.fitMessage = "Fitted on \(r.fsrsItems) reviews."
                        self.save(debounce: false)
                    }
                case .failure(let e):
                    self.fitMessage = "Not fitted: \(e.localizedDescription)"
                }
            }
        }
    }

    // MARK: reading

    static func forUpdate(_ backend: Backend, deck: Int64) throws -> Anki_DeckConfig_DeckConfigsForUpdate {
        var id = Anki_Decks_DeckId()
        id.did = deck
        return try backend.call(DeckConfigMethods.getDeckConfigsForUpdate, id)
    }

    /// Presets that at least one normal deck uses, with those decks. The empty "Default" deck is left out unless it is the only one.
    static func presets(_ backend: Backend) throws -> [PacePreset] {
        var names = Anki_Decks_GetDeckNamesRequest()
        names.skipEmptyDefault = true
        names.includeFiltered = false
        let decks: Anki_Decks_DeckNames = try backend.call(DecksMethods.getDeckNames, names)
        var byConfig: [Int64: [Int64]] = [:]
        for entry in decks.entries {
            var id = Anki_Decks_DeckId()
            id.did = entry.id
            guard let deck: Anki_Decks_Deck = try? backend.call(DecksMethods.getDeck, id), case .normal(let normal)? = deck.kind else { continue }
            byConfig[normal.configID, default: []].append(entry.id)
        }
        if byConfig.isEmpty { byConfig[1] = [1] }
        guard let any = byConfig.values.first?.first else { return [] }
        let update = try forUpdate(backend, deck: any)
        return update.allConfig.compactMap { c in
            guard let decks = byConfig[c.config.id] else { return nil }
            return PacePreset(id: c.config.id, name: c.config.name, decks: decks)
        }
    }

    /// Desired retention for a deck (by name) or, with nil, of the preset most decks use.
    static func desiredRetention(_ backend: Backend, deckName: String?) -> Double? {
        if let deckName {
            var req = Anki_Generic_String()
            req.val = deckName
            guard let id: Anki_Decks_DeckId = try? backend.call(DecksMethods.getDeckIdByName, req), id.did != 0,
                  let u = try? forUpdate(backend, deck: id.did) else { return nil }
            if u.currentDeck.limits.hasDesiredRetention { return Double(u.currentDeck.limits.desiredRetention) }
            return u.allConfig.first { $0.config.id == u.currentDeck.configID }.map { Double($0.config.config.desiredRetention) }
        }
        guard let presets = try? presets(backend), let top = presets.max(by: { $0.decks.count < $1.decks.count }),
              let deck = top.decks.first, let u = try? forUpdate(backend, deck: deck) else { return nil }
        return u.allConfig.first { $0.config.id == top.id }.map { Double($0.config.config.desiredRetention) }
    }

    /// First run: FSRS on and the chosen new-card limit on every preset in use (Kartei's defaults, docs/science-defaults.md).
    static func applyStartDefaults(_ backend: Backend, newPerDay: UInt32) throws {
        for preset in try presets(backend) {
            guard let deck = preset.decks.first else { continue }
            let u = try forUpdate(backend, deck: deck)
            guard var config = u.allConfig.first(where: { $0.config.id == preset.id })?.config else { continue }
            config.config.newPerDay = newPerDay
            if config.config.desiredRetention <= 0 { config.config.desiredRetention = PaceDefaults.desiredRetention }
            try write(backend, config: config, fsrs: true, deck: deck, update: u)
        }
    }
}

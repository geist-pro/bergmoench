// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The login a self-hosted Anki sync server returned. Kept in the Keychain; the password never is.
struct SyncAccount: Codable, Equatable {
    var hkey: String
    var endpoint: String
    var username: String

    var auth: Anki_Sync_SyncAuth {
        var a = Anki_Sync_SyncAuth()
        a.hkey = hkey
        a.endpoint = endpoint
        return a
    }

    /// "192.168.1.20:8080", without scheme or trailing slash, for display.
    var host: String {
        guard let url = URL(string: endpoint), let host = url.host else { return endpoint }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

enum SyncText {
    /// Turns what the person typed into a sync server URL, or explains what is wrong with it.
    /// No scheme: http for local names and addresses (most home servers), https otherwise. AnkiWeb is refused.
    static func endpoint(from typed: String) -> Result<String, SyncProblem> {
        var s = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .failure(.message("Enter the address of your sync server.")) }
        if !s.contains("://") {
            let hostPart = s.split(separator: "/").first.map(String.init) ?? s
            let host = hostPart.split(separator: ":").first.map(String.init)?.lowercased() ?? hostPart
            let local = host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa")
                || host.allSatisfy { $0.isNumber || $0 == "." } || host.hasPrefix("[")
            s = (local ? "http://" : "https://") + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return .failure(.message("That address does not look right. It should look like http://192.168.1.20:8080/."))
        }
        if host.lowercased().hasSuffix("ankiweb.net") {
            return .failure(.message("Bergmönch cannot sync with AnkiWeb: its terms only allow Anki's own apps. Use a self-hosted Anki sync server."))
        }
        if !s.hasSuffix("/") { s += "/" }
        return .success(s)
    }

    /// "Synced just now", "Synced 2 min ago", "Synced 3 h ago", "Synced yesterday", "Synced 12 Nov".
    static func syncedAgo(_ last: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let last else { return "Not synced yet" }
        let secs = now.timeIntervalSince(last)
        if secs < 60 { return "Synced just now" }
        if secs < 3600 { return "Synced \(Int(secs / 60)) min ago" }
        if calendar.isDate(last, inSameDayAs: now) || secs < 6 * 3600 { return "Synced \(Int(secs / 3600)) h ago" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(last, inSameDayAs: y) { return "Synced yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(last, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy")
        return "Synced \(f.string(from: last))"
    }

    /// Anki's backend messages talk about AnkiWeb and Anki versions; say what happened in plain words instead.
    static func plain(_ raw: String) -> String {
        let m = raw.lowercased()
        func has(_ s: String) -> Bool { m.contains(s.lowercased()) }
        if has("password was incorrect") {
            return "The server did not accept that username and password."
        }
        if has("invalid sync server") || has("relative url") || has("invalid url") {
            return "That server address does not look right. It should look like http://192.168.1.20:8080/."
        }
        if has("timed out") || has("timeout") {
            return "The server took too long to answer. Check that it is running, then try again."
        }
        if has("internet connection") || has("network error") || has("error sending request") || has("connection refused")
            || has("dns") || has("connect") || has("offline") {
            return "Could not reach the sync server. Check the address, that the server is running, and that this device is online."
        }
        if has("only one copy") { return "Another device is syncing right now. Try again in a few minutes." }
        if has("encountered a problem") { return "The sync server had a problem. Try again in a few minutes." }
        if has("too old") { return "The sync server needs a newer version of Bergmönch." }
        if has("clock") { return "This device's clock is off. Set it to the correct time, then sync again." }
        if has("check database") || has("sanity") {
            return "This device and the server disagree about your collection. Sync again; if this keeps happening, choose a one-way sync in Settings."
        }
        if has("please sync again") { return "Sync was interrupted. Please sync again." }
        if has("interrupted") || has("aborted") { return "Sync was stopped before it finished." }
        if has("media") { return "Cards synced, but media files did not: \(raw)" }
        return "Sync did not finish: \(raw)"
    }
}

enum SyncProblem: Error, Equatable {
    case message(String)
    var text: String { switch self { case .message(let s): return s } }
}

/// Runs login, collection sync, the one-way choice and media sync against a self-hosted Anki sync server.
/// One instance for the app; the home topline and the Settings section both observe it.
@MainActor
@Observable
final class SyncController {
    static let shared = SyncController()

    enum Status: Equatable {
        case idle
        case working(String)
        /// Both sides changed in ways a normal sync cannot merge: the person must pick a direction.
        case needsChoice
        case failed(String)
    }

    private(set) var account: SyncAccount?
    private(set) var status: Status = .idle
    private(set) var lastSync: Date?
    /// True while a review session is open: coming back to the app then does not start a sync under the learner.
    var pausedForReview = false
    private(set) var serverMessage: String?
    /// Server media USN from the sync that asked for a one-way choice, so media can follow the full sync.
    private var pendingMediaUsn: Int32?

    private weak var store: DeckStore?
    private var scope = "default"
    private var keychain = Keychain(service: "app.kartei.sync")
    private var defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []

    var isBusy: Bool { if case .working = status { return true }; return false }

    /// Connect to the opened collection. `scope` separates collections (each KARTEI_DATA_DIR in tests is its own device).
    func attach(_ store: DeckStore, scope: String, keychain: Keychain? = nil, defaults: UserDefaults? = nil, autoSync: Bool = true) {
        let first = self.store == nil || self.scope != scope
        self.store = store
        self.scope = scope
        if let keychain { self.keychain = keychain }
        if let defaults { self.defaults = defaults }
        guard first else { return }
        do { account = try self.keychain.value(SyncAccount.self, for: scope) } catch {
            account = nil
            status = .failed("The saved sync login could not be read. Log in again in Settings.")
        }
        lastSync = self.defaults.object(forKey: lastKey) as? Date
        #if DEBUG
        if runTestHooks() { return }
        #endif
        if autoSync {
            observeForeground()
            if account != nil { sync() }
        }
    }

    #if DEBUG
    /// Debug-only hooks for the scripted two-device run: KARTEI_TEST_SYNC="http://host:port/ user pass" logs in
    /// (if not logged in yet); KARTEI_TEST_SYNC_CHOICE=upload|download answers the one-way choice.
    /// KARTEI_TEST_ANSWER=1 answers one card "Good" in the first deck with cards, then syncs. Returns true when a hook took over.
    private func runTestHooks() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if account == nil, let spec = env["KARTEI_TEST_SYNC"]?.split(separator: " ").map(String.init), spec.count == 3 {
            Task { if let p = await login(server: spec[0], username: spec[1], password: spec[2]) { status = .failed(p.text) } }
            return true
        }
        if env["KARTEI_TEST_ANSWER"] != nil, let backend = store?.backend {
            Task {
                let id: Int64? = await Task.detached {
                    var tree = Anki_Decks_DeckTreeRequest()
                    tree.now = Int64(Date().timeIntervalSince1970)
                    guard let t: Anki_Decks_DeckTreeNode = try? backend.call(DecksMethods.deckTree, tree),
                          let deck = t.children.first(where: { $0.newCount + $0.learnCount + $0.reviewCount > 0 }) else { return nil }
                    var did = Anki_Decks_DeckId()
                    did.did = deck.deckID
                    let _: Anki_Collection_OpChanges? = try? backend.call(DecksMethods.setCurrentDeck, did)
                    var q = Anki_Scheduler_GetQueuedCardsRequest()
                    q.fetchLimit = 1
                    guard let queued: Anki_Scheduler_QueuedCards = try? backend.call(SchedulerMethods.getQueuedCards, q), let card = queued.cards.first else { return nil }
                    var a = Anki_Scheduler_CardAnswer()
                    a.cardID = card.card.id
                    a.currentState = card.states.current
                    a.newState = card.states.good
                    a.rating = .good
                    a.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
                    a.millisecondsTaken = 5000
                    let _: Anki_Collection_OpChanges? = try? backend.call(SchedulerMethods.answerCard, a)
                    return card.card.id
                }.value
                print("KARTEI_TEST_ANSWER answered card \(id.map(String.init) ?? "none")")
                store?.refresh()
                sync()
            }
            return true
        }
        return false
    }

    private var testChoice: Bool? {
        switch ProcessInfo.processInfo.environment["KARTEI_TEST_SYNC_CHOICE"] {
        case "upload": return true
        case "download": return false
        default: return nil
        }
    }
    #endif

    private var lastKey: String { "kartei.sync.last.\(scope)" }

    private func observeForeground() {
        guard observers.isEmpty else { return }
        #if os(iOS)
        let name = UIApplication.willEnterForegroundNotification
        #else
        let name = NSApplication.didBecomeActiveNotification
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.account != nil, !self.pausedForReview else { return }
                // Coming back after a short look elsewhere should not sync every time.
                if let last = self.lastSync, Date.now.timeIntervalSince(last) < 120 { return }
                self.sync()
            }
        })
    }

    // MARK: - Login

    /// Log in and store the returned host key. Then sync straight away.
    func login(server: String, username: String, password: String) async -> SyncProblem? {
        guard let backend = store?.backend else { return .message("Your collection is still opening. Try again in a moment.") }
        let endpoint: String
        switch SyncText.endpoint(from: server) {
        case .success(let e): endpoint = e
        case .failure(let p): return p
        }
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty else { return .message("Enter the username and password set on your sync server.") }
        status = .working("Logging in")
        let result: Result<String, Error> = await Task.detached {
            var req = Anki_Sync_SyncLoginRequest()
            req.username = user
            req.password = password
            req.endpoint = endpoint
            do {
                let auth: Anki_Sync_SyncAuth = try backend.call(SyncMethods.syncLogin, req)
                return .success(auth.hkey)
            } catch { return .failure(error) }
        }.value
        switch result {
        case .failure(let error):
            status = .idle
            return .message(SyncText.plain(error.localizedDescription))
        case .success(let hkey):
            let acct = SyncAccount(hkey: hkey, endpoint: endpoint, username: user)
            do { try keychain.set(acct, for: scope) } catch {
                status = .idle
                return .message("Logged in, but the login could not be saved in the Keychain: \(error.localizedDescription)")
            }
            account = acct
            status = .idle
            sync()
            return nil
        }
    }

    func logout() {
        try? keychain.remove(scope)
        account = nil
        lastSync = nil
        serverMessage = nil
        defaults.removeObject(forKey: lastKey)
        status = .idle
    }

    // MARK: - Sync

    /// Normal sync, with media. A required one-way sync is never chosen silently when both sides have cards.
    func sync() {
        guard let backend = store?.backend, let account, !isBusy else { return }
        status = .working("Syncing")
        Task.detached { [auth = account.auth] in
            do {
                var req = Anki_Sync_SyncCollectionRequest()
                req.auth = auth
                req.syncMedia = true
                let out: Anki_Sync_SyncCollectionResponse = try backend.call(SyncMethods.syncCollection, req)
                let message = out.serverMessage.isEmpty ? nil : out.serverMessage
                let newEndpoint = out.hasNewEndpoint ? out.newEndpoint : nil
                await MainActor.run {
                    self.serverMessage = message
                    if let newEndpoint { self.moveEndpoint(newEndpoint) }
                }
                switch out.required {
                case .fullSync:
                    await MainActor.run {
                        self.pendingMediaUsn = out.serverMediaUsn
                        self.status = .needsChoice
                        #if DEBUG
                        if let upload = self.testChoice { self.resolveFullSync(upload: upload) }
                        #endif
                    }
                    return
                case .fullDownload:  // this device has no cards: nothing to lose by downloading
                    try await self.runFull(backend, auth: auth, upload: false, mediaUsn: out.serverMediaUsn)
                case .fullUpload:  // the server has no cards: nothing to lose by uploading
                    try await self.runFull(backend, auth: auth, upload: true, mediaUsn: out.serverMediaUsn)
                default:
                    try await self.waitForMedia(backend)
                }
                await self.finish(nil)
            } catch {
                await self.finish(error)
            }
        }
    }

    /// The person's answer to the one-way choice. Upload replaces the server's copy; download replaces this device's.
    func resolveFullSync(upload: Bool) {
        guard let backend = store?.backend, let account, status == .needsChoice else { return }
        let usn = pendingMediaUsn
        pendingMediaUsn = nil
        status = .working(upload ? "Uploading this device" : "Downloading from server")
        Task.detached { [auth = account.auth] in
            do {
                try await self.runFull(backend, auth: auth, upload: upload, mediaUsn: usn)
                await self.finish(nil)
            } catch { await self.finish(error) }
        }
    }

    func cancelFullSync() {
        guard status == .needsChoice else { return }
        pendingMediaUsn = nil
        status = .idle
    }

    /// Ask for a one-way sync on purpose (Settings), e.g. after "the server and this device disagree".
    func requestFullSync() {
        guard account != nil, !isBusy else { return }
        status = .needsChoice
    }

    nonisolated private func runFull(_ backend: Backend, auth: Anki_Sync_SyncAuth, upload: Bool, mediaUsn: Int32?) async throws {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        if let mediaUsn { req.serverUsn = mediaUsn }
        let _: Anki_Generic_Empty = try backend.call(SyncMethods.fullUploadOrDownload, req)
        try await waitForMedia(backend)
    }

    /// Media runs in the backend's background; follow it until done, surfacing its error if it had one.
    nonisolated private func waitForMedia(_ backend: Backend) async throws {
        while true {
            let s: Anki_Sync_MediaSyncStatusResponse = try backend.call(SyncMethods.mediaSyncStatus)
            if !s.active { return }
            let checked = s.progress.checked
            await MainActor.run { self.status = .working(checked.isEmpty ? "Syncing media" : "Syncing media · \(checked)") }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func finish(_ error: Error?) {
        if let error {
            let text = SyncText.plain(error.localizedDescription)
            status = .failed(text)
            if text.hasPrefix("The server did not accept") {
                // The stored key no longer works (password changed, server reset): ask to log in again.
                status = .failed(text + " Log in again in Settings.")
            }
        } else {
            status = .idle
            lastSync = .now
            defaults.set(lastSync, forKey: lastKey)
        }
        store?.refresh()
        if let store { Reach.storeDidUpdate(store) }
    }

    private func moveEndpoint(_ endpoint: String) {
        guard var acct = account, case .success(let e) = SyncText.endpoint(from: endpoint) else { return }
        acct.endpoint = e
        try? keychain.set(acct, for: scope)
        account = acct
    }
}

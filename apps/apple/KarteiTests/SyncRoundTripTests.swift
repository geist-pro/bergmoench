// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

/// Two collections ("devices") against a real local Anki sync server. Opt-in, because it replaces the account's
/// collection on that server: start a throwaway server and pass its address and login, e.g.
///   SYNC_USER1=kai:test SYNC_BASE=<scratch dir> SYNC_HOST=127.0.0.1 SYNC_PORT=27702 core/ffi/target/release/examples/syncserver
///   TEST_RUNNER_KARTEI_SYNC_TEST="http://127.0.0.1:27702/ kai test" xcodebuild … test
final class SyncRoundTripTests: XCTestCase {
    private var endpoint = "http://127.0.0.1:27702/"
    private var user = "kai"
    private var pass = "test"
    private var dirs: [URL] = []

    override func setUpWithError() throws {
        guard let spec = ProcessInfo.processInfo.environment["KARTEI_SYNC_TEST"]?.split(separator: " "), spec.count == 3 else {
            throw XCTSkip("set KARTEI_SYNC_TEST=\"http://host:port/ user pass\" for a throwaway sync server")
        }
        (endpoint, user, pass) = (String(spec[0]), String(spec[1]), String(spec[2]))
        var reachable = false
        let done = expectation(description: "probe")
        URLSession.shared.dataTask(with: URL(string: endpoint)!) { _, response, _ in reachable = response != nil; done.fulfill() }.resume()
        wait(for: [done], timeout: 3)
        try XCTSkipUnless(reachable, "no sync server at \(endpoint)")
    }

    override func tearDown() { for d in dirs { try? FileManager.default.removeItem(at: d) } }

    private func device(_ name: String) throws -> Backend {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-sync-\(name)-\(UUID().uuidString)")
        dirs.append(dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("media"), withIntermediateDirectories: true)
        let b = try Backend()
        var open = Anki_Collection_OpenCollectionRequest()
        open.collectionPath = dir.appendingPathComponent("collection.anki2").path
        open.mediaFolderPath = dir.appendingPathComponent("media").path
        open.mediaDbPath = dir.appendingPathComponent("media.db").path
        try b.run(CollectionMethods.openCollection, open)
        return b
    }

    private func login(_ b: Backend, password: String? = nil) throws -> Anki_Sync_SyncAuth {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = user
        req.password = password ?? pass
        req.endpoint = endpoint
        return try b.call(SyncMethods.syncLogin, req)
    }

    private func sync(_ b: Backend, _ auth: Anki_Sync_SyncAuth) throws -> Anki_Sync_SyncCollectionResponse {
        var req = Anki_Sync_SyncCollectionRequest()
        req.auth = auth
        req.syncMedia = true
        let out: Anki_Sync_SyncCollectionResponse = try b.call(SyncMethods.syncCollection, req)
        try waitMedia(b)
        return out
    }

    private func full(_ b: Backend, _ auth: Anki_Sync_SyncAuth, upload: Bool, usn: Int32) throws {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        req.serverUsn = usn
        let _: Anki_Generic_Empty = try b.call(SyncMethods.fullUploadOrDownload, req)
        try waitMedia(b)
    }

    private func waitMedia(_ b: Backend) throws {
        for _ in 0..<200 {
            let s: Anki_Sync_MediaSyncStatusResponse = try b.call(SyncMethods.mediaSyncStatus)
            if !s.active { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("media sync did not finish")
    }

    private func deckNames(_ b: Backend) throws -> Set<String> {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = 0
        let tree: Anki_Decks_DeckTreeNode = try b.call(DecksMethods.deckTree, req)
        return Set(tree.children.map(\.name)).subtracting(["Default"])
    }

    private func count(_ b: Backend, _ search: String) throws -> Int {
        var req = Anki_Search_SearchRequest()
        req.search = search
        let ids: Anki_Search_SearchResponse = try b.call(SearchMethods.searchCards, req)
        return ids.ids.count
    }

    /// Point the review queue at the imported deck (the queue follows the current deck).
    private func studyFirstDeck(_ b: Backend) throws {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = Int64(Date().timeIntervalSince1970)
        let tree: Anki_Decks_DeckTreeNode = try b.call(DecksMethods.deckTree, req)
        var id = Anki_Decks_DeckId()
        id.did = try XCTUnwrap(tree.children.first { $0.newCount + $0.reviewCount + $0.learnCount > 0 }).deckID
        let _: Anki_Collection_OpChanges = try b.call(DecksMethods.setCurrentDeck, id)
    }

    private func answerOne(_ b: Backend) throws -> Int64 {
        var q = Anki_Scheduler_GetQueuedCardsRequest()
        q.fetchLimit = 1
        let queued: Anki_Scheduler_QueuedCards = try b.call(SchedulerMethods.getQueuedCards, q)
        let card = try XCTUnwrap(queued.cards.first)
        var a = Anki_Scheduler_CardAnswer()
        a.cardID = card.card.id
        a.currentState = card.states.current
        a.newState = card.states.good
        a.rating = .good
        a.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        a.millisecondsTaken = 4000
        let _: Anki_Collection_OpChanges = try b.call(SchedulerMethods.answerCard, a)
        return card.card.id
    }

    func testWrongPasswordIsPlain() throws {
        let b = try device("wrong")
        XCTAssertThrowsError(try login(b, password: "nope")) { error in
            XCTAssertEqual(SyncText.plain(error.localizedDescription), "The server did not accept that username and password.")
        }
    }

    func testUnreachableServerIsPlain() throws {
        let b = try device("offline")
        var req = Anki_Sync_SyncLoginRequest()
        req.username = user
        req.password = pass
        req.endpoint = "http://127.0.0.1:9/"
        XCTAssertThrowsError(try b.call(SyncMethods.syncLogin, req, returning: Anki_Sync_SyncAuth.self)) { error in
            XCTAssertTrue(SyncText.plain(error.localizedDescription).hasPrefix("Could not reach"), error.localizedDescription)
        }
    }

    /// Device A uploads a deck and a review; device B, starting empty, downloads and sees both;
    /// a review on B comes back to A by a normal (incremental) sync.
    func testTwoDevicesRoundTrip() throws {
        let a = try device("A")
        let apkg = try XCTUnwrap(TempCollection.package("sample-01"))
        var imp = Anki_ImportExport_ImportAnkiPackageRequest()
        imp.packagePath = apkg.path
        imp.options.mergeNotetypes = true
        let _: Anki_ImportExport_ImportResponse = try a.call(ImportExportMethods.importAnkiPackage, imp)
        try studyFirstDeck(a)
        let authA = try login(a)
        XCTAssertFalse(authA.hkey.isEmpty)

        // First contact: either the server is empty (upload offered alone) or it holds an older run (both offered).
        let first = try sync(a, authA)
        if [.fullUpload, .fullSync].contains(first.required) {
            try full(a, authA, upload: true, usn: first.serverMediaUsn)
        }
        let answered = try answerOne(a)
        XCTAssertEqual(try sync(a, authA).required, .noChanges, "a normal sync merges and reports nothing left to do")

        let b = try device("B")
        let authB = try login(b)
        let firstB = try sync(b, authB)
        XCTAssertEqual(firstB.required, .fullDownload, "an empty device is never offered an upload")
        try full(b, authB, upload: false, usn: firstB.serverMediaUsn)

        XCTAssertEqual(try deckNames(b), try deckNames(a))
        XCTAssertFalse(try deckNames(b).isEmpty)
        XCTAssertEqual(try count(b, "cid:\(answered) rated:1"), 1, "the review answered on A is on B")

        try studyFirstDeck(b)
        let answeredOnB = try answerOne(b)
        XCTAssertEqual(try sync(b, authB).required, .noChanges, "a normal sync merges and reports nothing left to do")
        XCTAssertEqual(try sync(a, authA).required, .noChanges, "a normal sync merges and reports nothing left to do")
        XCTAssertEqual(try count(a, "cid:\(answeredOnB) rated:1"), 1, "and B's review comes back to A")
        XCTAssertEqual(try sync(a, authA).required, .noChanges)
    }
}

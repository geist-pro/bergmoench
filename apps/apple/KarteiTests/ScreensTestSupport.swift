// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import XCTest
@testable import Kartei

/// A real Anki collection in a temporary folder, with one or more of the sample decks imported.
final class TempCollection {
    let backend: Backend
    let dir: URL

    init(decks: [String] = ["sample-01"]) throws {
        backend = try Backend()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-screens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("media"), withIntermediateDirectories: true)
        var open = Anki_Collection_OpenCollectionRequest()
        open.collectionPath = dir.appendingPathComponent("collection.anki2").path
        open.mediaFolderPath = dir.appendingPathComponent("media").path
        open.mediaDbPath = dir.appendingPathComponent("media.db").path
        try backend.run(CollectionMethods.openCollection, open)
        for name in decks {
            guard let url = Self.package(name) else { throw BackendFailure(message: "missing sample deck \(name)") }
            var req = Anki_ImportExport_ImportAnkiPackageRequest()
            req.packagePath = url.path
            req.options.mergeNotetypes = true
            let _: Anki_ImportExport_ImportResponse = try backend.call(ImportExportMethods.importAnkiPackage, req)
        }
    }

    /// The sample decks live beside the tests (Fixtures/, built by make_fixtures.py) and ship in the test bundle.
    static func package(_ name: String) -> URL? {
        if let url = Bundle(for: TempCollection.self).url(forResource: name, withExtension: "apkg") { return url }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).apkg")
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }

    func cardIDs(_ search: String) throws -> [Int64] {
        var req = Anki_Search_SearchRequest()
        req.search = search
        let resp: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, req)
        return resp.ids
    }

    /// Answer cards now with one rating (creates real review log entries).
    func grade(_ ids: [Int64], _ rating: Anki_Scheduler_CardAnswer.Rating) throws {
        var req = Anki_Scheduler_GradeNowRequest()
        req.cardIds = ids
        req.rating = rating
        try backend.run(SchedulerMethods.gradeNow, req)
    }

    deinit {
        _ = try? backend.run(CollectionMethods.closeCollection, Anki_Collection_CloseCollectionRequest())
        try? FileManager.default.removeItem(at: dir)
    }
}

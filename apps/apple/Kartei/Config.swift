// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation

extension Backend {
    /// Read a JSON value from the collection's config (it travels with the collection when it syncs).
    func config<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        var k = Anki_Generic_String()
        k.val = key
        guard let json: Anki_Generic_Json = try? call(ConfigMethods.getConfigJson, k) else { return nil }
        return try? JSONDecoder().decode(T.self, from: json.json)
    }

    /// Write a JSON value to the collection's config, without an undo entry.
    func setConfig<T: Encodable>(_ key: String, _ value: T) {
        var req = Anki_Config_SetConfigJsonRequest()
        req.key = key
        req.valueJson = (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
        req.undoable = false
        let _: Anki_Generic_Empty? = try? call(ConfigMethods.setConfigJsonNoUndo, req)
    }
}

/// Kartei's own study settings, stored in the collection config. Defaults follow docs/science-defaults.md.
@Observable
final class StudyPrefs {
    enum Detail: String, Codable { case simple, full }

    static let detailKey = "kartei.detail"
    static let onboardedKey = "kartei.onboarded"

    /// Simple (Forgot / Got it) is the default for new users: two and four buttons are equally accurate for FSRS
    /// and two buttons remove the Hard misuse. Anki users can pick Full.
    var detail: Detail = .simple
    var onboarded = true
    var loaded = false

    private var backend: Backend?

    func load(_ backend: Backend) {
        self.backend = backend
        detail = backend.config(Self.detailKey, as: Detail.self) ?? .simple
        onboarded = backend.config(Self.onboardedKey, as: Bool.self) ?? false
        loaded = true
    }

    func setDetail(_ d: Detail) { detail = d; backend?.setConfig(Self.detailKey, d) }
    func finishOnboarding() { onboarded = true; backend?.setConfig(Self.onboardedKey, true) }
}

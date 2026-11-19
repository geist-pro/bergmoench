// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import KarteiCore
import SwiftProtobuf

struct BackendFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Anki's backend. Every call is one protobuf message in and one out. Calls block, so use them off the main thread.
final class Backend: @unchecked Sendable {
    private let handle: OpaquePointer

    init(languages: [String] = ["en"]) throws {
        var msg = Anki_Backend_BackendInit()
        msg.preferredLangs = languages
        let data = try msg.serializedData()
        var err = KarteiBytes(ptr: nil, len: 0, ok: false)
        let opened = data.withUnsafeBytes { raw in
            kartei_open(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &err)
        }
        guard let opened else {
            let text = err.ptr.map { String(decoding: UnsafeBufferPointer(start: $0, count: err.len), as: UTF8.self) } ?? "could not start the backend"
            kartei_free(err)
            throw BackendFailure(message: text)
        }
        handle = opened
    }

    deinit { kartei_close(handle) }

    func call<Output: Message>(_ method: BackendMethod, _ input: any Message = Anki_Generic_Empty(), returning: Output.Type = Output.self) throws -> Output {
        let data: Data = try input.serializedData()
        let result = data.withUnsafeBytes { raw in
            kartei_command(handle, method.service, method.method, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
        defer { kartei_free(result) }
        let bytes = result.ptr.map { Data(bytes: $0, count: result.len) } ?? Data()
        guard result.ok else {
            let err = try? Anki_Backend_BackendError(serializedBytes: bytes)
            throw BackendFailure(message: err?.message ?? "backend error")
        }
        return try Output(serializedBytes: bytes)
    }

    @discardableResult
    func run(_ method: BackendMethod, _ input: any Message = Anki_Generic_Empty()) throws -> Anki_Generic_Empty {
        try call(method, input)
    }

    static var ankiVersion: String {
        let b = kartei_anki_version()
        defer { kartei_free(b) }
        return b.ptr.map { String(decoding: UnsafeBufferPointer(start: $0, count: b.len), as: UTF8.self) } ?? ""
    }
}

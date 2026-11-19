// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.core

import com.google.protobuf.MessageLite
import com.google.protobuf.Parser

internal object Native {
    init { System.loadLibrary("kartei_core") }
    @JvmStatic external fun open(init: ByteArray): Long
    @JvmStatic external fun command(handle: Long, service: Int, method: Int, input: ByteArray): ByteArray
    @JvmStatic external fun close(handle: Long)
    @JvmStatic external fun version(): String
    @JvmStatic external fun capStates(states: ByteArray, daysLeft: Int): ByteArray
}

class BackendFailure(message: String) : Exception(message)

/** Anki's backend. Every call is one protobuf message in and one out. Calls block, so keep them off the main thread. */
class Backend(languages: List<String> = listOf("en")) : AutoCloseable {
    private val handle: Long = Native.open(anki.backend.BackendInit.newBuilder().addAllPreferredLangs(languages).build().toByteArray())
        .also { if (it == 0L) throw BackendFailure("could not start the backend") }

    fun <T : MessageLite> call(method: BackendMethod, input: MessageLite, parser: Parser<T>): T {
        val framed = Native.command(handle, method.service, method.method, input.toByteArray())
        val payload = framed.copyOfRange(1, framed.size)
        if (framed[0].toInt() != 1) throw BackendFailure(anki.backend.BackendError.parseFrom(payload).message)
        return parser.parseFrom(payload)
    }

    fun run(method: BackendMethod, input: MessageLite = anki.generic.Empty.getDefaultInstance()) {
        call(method, input, anki.generic.Empty.parser())
    }

    override fun close() = Native.close(handle)

    companion object { val ankiVersion: String get() = Native.version() }
}

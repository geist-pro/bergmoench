// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.core

import com.google.protobuf.ByteString

/** Read a raw JSON value from the collection's config (it travels with the collection when it syncs); null if unset. */
fun Backend.configJson(key: String): String? = runCatching {
    call(ConfigMethods.getConfigJson, anki.generic.String.newBuilder().setVal(key).build(), anki.generic.Json.parser()).json.toStringUtf8()
}.getOrNull()

/** Write a raw JSON value to the collection's config, without an undo entry. */
fun Backend.setConfigJson(key: String, json: String) {
    runCatching {
        run(ConfigMethods.setConfigJsonNoUndo, anki.config.SetConfigJsonRequest.newBuilder().setKey(key)
            .setValueJson(ByteString.copyFromUtf8(json)).setUndoable(false).build())
    }
}

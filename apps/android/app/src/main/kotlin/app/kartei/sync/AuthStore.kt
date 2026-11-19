// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.sync

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** What a successful login leaves behind. The password is never kept: the server's host key stands in for it. */
data class SyncLogin(val username: String, val endpoint: String, val hkey: String) {
    fun encode(): String = listOf("v1", username, endpoint, hkey).joinToString("|") { b64(it) }

    companion object {
        private fun b64(s: String) = Base64.getEncoder().encodeToString(s.toByteArray(Charsets.UTF_8))
        private fun unb64(s: String) = String(Base64.getDecoder().decode(s), Charsets.UTF_8)

        fun decode(text: String): SyncLogin? = runCatching {
            val parts = text.split('|').map(::unb64)
            if (parts.size != 4 || parts[0] != "v1" || parts[3].isEmpty()) null else SyncLogin(parts[1], parts[2], parts[3])
        }.getOrNull()
    }
}

/** Encrypts and decrypts small secrets. */
interface Sealer {
    fun seal(plain: ByteArray): ByteArray
    fun open(sealed: ByteArray): ByteArray
}

/**
 * AES-256-GCM with a key that lives in the Android Keystore (hardware-backed where the device has it) and never
 * leaves it. Output is IV (12 bytes) followed by ciphertext and tag. Chosen over EncryptedSharedPreferences,
 * which androidx has deprecated, and it needs no extra library.
 */
class KeystoreSealer(private val alias: String = "kartei.sync.auth") : Sealer {
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return gen.generateKey()
    }

    override fun seal(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return c.iv + c.doFinal(plain)
    }

    override fun open(sealed: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
        return c.doFinal(sealed, 12, sealed.size - 12)
    }

    fun forget() = runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias) }
}

/** Login kept sealed in app-private preferences (excluded from backup: the manifest sets allowBackup=false). */
class AuthStore(context: Context, private val sealer: Sealer = KeystoreSealer()) {
    private val prefs = context.getSharedPreferences("kartei.sync", Context.MODE_PRIVATE)

    fun load(): SyncLogin? {
        val blob = prefs.getString("auth", null) ?: return null
        return runCatching { SyncLogin.decode(String(sealer.open(Base64.getDecoder().decode(blob)), Charsets.UTF_8)) }.getOrNull()
    }

    fun save(login: SyncLogin) {
        val blob = Base64.getEncoder().encodeToString(sealer.seal(login.encode().toByteArray(Charsets.UTF_8)))
        prefs.edit().putString("auth", blob).apply()
    }

    fun clear() {
        prefs.edit().remove("auth").remove("lastSync").apply()
        (sealer as? KeystoreSealer)?.forget()
    }

    var lastSyncMillis: Long
        get() = prefs.getLong("lastSync", 0L)
        set(v) { prefs.edit().putLong("lastSync", v).apply() }

    /** Last server address typed, kept so a failed login doesn't make the person type it again. Not secret. */
    var lastServer: String
        get() = prefs.getString("server", "") ?: ""
        set(v) { prefs.edit().putString("server", v).apply() }
}

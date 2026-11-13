package com.wimg.app.services

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The saved bank PIN, encrypted with an AES-256-GCM key that lives in the
 * Android Keystore (hardware-backed where the phone has it) and never leaves
 * it. Only the ciphertext is in the app's preferences. Counterpart of the iOS
 * Keychain entry `fints_pin`.
 *
 * No user authentication on the key: the daily background fetch must read the
 * PIN while the phone is locked, as on iOS (kSecAttrAccessibleAfterFirstUnlock).
 */
object PinStore {
    private const val PREFS = "wimg_fints"
    private const val KEY_ENC = "fints_pin_enc"
    /** Plain-text PIN from early builds; moved by [adoptLegacy]. */
    private const val KEY_LEGACY = "fints_pin"
    private const val ALIAS = "wimg_fints_pin"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    /** Each bank connection has its own ciphertext; the Keystore key is shared. */
    private fun slot(id: String) = "$KEY_ENC:$id"

    private fun encrypt(pin: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val ct = cipher.doFinal(pin.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(ct, Base64.NO_WRAP)
    }

    private fun decrypt(packed: String): String {
        val (iv, ct) = packed.split(":", limit = 2).map { Base64.decode(it, Base64.NO_WRAP) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
        return String(cipher.doFinal(ct), Charsets.UTF_8)
    }

    @Synchronized
    fun set(context: Context, id: String, pin: String) {
        prefs(context).edit().putString(slot(id), encrypt(pin)).apply()
    }

    @Synchronized
    fun get(context: Context, id: String): String? {
        val p = prefs(context)
        val packed = p.getString(slot(id), null) ?: return null
        return runCatching { decrypt(packed) }.getOrElse {
            // Key gone (app data restored elsewhere, keystore reset): the PIN is
            // unreadable, so forget it and ask for it again.
            p.edit().remove(slot(id)).apply()
            null
        }
    }

    fun has(context: Context, id: String): Boolean = prefs(context).contains(slot(id))

    @Synchronized
    fun clear(context: Context, id: String) {
        prefs(context).edit().remove(slot(id)).apply()
    }

    /** Every saved PIN (Settings › delete all data). */
    @Synchronized
    fun clearAll(context: Context) {
        val p = prefs(context)
        p.edit().apply { p.all.keys.filter { it.startsWith(KEY_ENC) || it == KEY_LEGACY }.forEach { remove(it) } }.apply()
    }

    /** Moves the single PIN of older builds (encrypted or, before that, plain) to [id]. */
    @Synchronized
    fun adoptLegacy(context: Context, id: String) {
        val p = prefs(context)
        val pin = p.getString(KEY_LEGACY, null) ?: p.getString(KEY_ENC, null)?.let { runCatching { decrypt(it) }.getOrNull() }
        if (pin != null) runCatching { set(context, id, pin) }
        p.edit().remove(KEY_ENC).remove(KEY_LEGACY).apply()
    }
}

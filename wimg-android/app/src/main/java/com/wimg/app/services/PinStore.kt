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
    /** Plain-text PIN from builds before 2026-11-13; moved into KEY_ENC on first read. */
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

    @Synchronized
    fun set(context: Context, pin: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val ct = cipher.doFinal(pin.toByteArray(Charsets.UTF_8))
        val packed = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(ct, Base64.NO_WRAP)
        prefs(context).edit().putString(KEY_ENC, packed).remove(KEY_LEGACY).apply()
    }

    @Synchronized
    fun get(context: Context): String? {
        val p = prefs(context)
        p.getString(KEY_LEGACY, null)?.let { plain ->
            // One-time move of an old plain PIN. If encryption fails, keep it as it was.
            return runCatching { set(context, plain); plain }.getOrDefault(plain)
        }
        val packed = p.getString(KEY_ENC, null) ?: return null
        return runCatching {
            val (iv, ct) = packed.split(":", limit = 2).map { Base64.decode(it, Base64.NO_WRAP) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
            String(cipher.doFinal(ct), Charsets.UTF_8)
        }.getOrElse {
            // Key gone (app data restored elsewhere, keystore reset): the PIN is
            // unreadable, so forget it and ask for it again.
            p.edit().remove(KEY_ENC).apply()
            null
        }
    }

    fun has(context: Context): Boolean = prefs(context).let { it.contains(KEY_ENC) || it.contains(KEY_LEGACY) }

    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ENC).remove(KEY_LEGACY).apply()
    }
}

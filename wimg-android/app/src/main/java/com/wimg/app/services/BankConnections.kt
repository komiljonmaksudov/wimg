package com.wimg.app.services

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * One bank login on this device. The PIN is not in here: it lives encrypted in
 * [PinStore] under [id]. Nothing of this is ever synchronised.
 */
@Serializable
data class BankConnection(
    val id: String,
    val blz: String,
    val kennung: String,
    /** Bank name from the catalog; also the account id its statements land in. */
    val name: String,
    val tanMedium: String? = null,
    val lastFetchAt: Long = 0,
    val lastFetchNew: Int = 0,
    /**
     * Statements come as CAMT (HKCAZ) instead of MT940 (HKKAZ). Set by itself
     * when one format fails at the bank and the other works (Comdirect's MT940
     * answered 9900 from 2026-11-16); switches back the same way.
     */
    val camt: Boolean = false,
    /**
     * The FinTS system id the bank gave this login. Kept so a sign-in asks for no
     * new one (python-fints does the same); null until the first sign-in.
     */
    val systemId: String? = null,
)

/** The bank logins on this device, newest last. */
object BankConnections {
    private const val PREFS = "wimg_fints"
    private const val KEY = "fints_connections"
    private val json = Json { ignoreUnknownKeys = true }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun idFor(blz: String, kennung: String) = "$blz/$kennung"

    @Synchronized
    fun all(context: Context): List<BankConnection> {
        val p = prefs(context)
        p.getString(KEY, null)?.let { s -> return runCatching { json.decodeFromString<List<BankConnection>>(s) }.getOrDefault(emptyList()) }
        // Builds before 2026-11-13 kept exactly one login in loose keys.
        val blz = p.getString("fints_blz", null) ?: return emptyList()
        val kennung = p.getString("fints_kennung", null) ?: ""
        val old = BankConnection(
            id = idFor(blz, kennung), blz = blz, kennung = kennung,
            name = p.getString("fints_bank_name", null) ?: "",
            tanMedium = p.getString("fints_tan_medium", null),
            lastFetchAt = p.getLong("fints_last_fetch_at", 0),
            lastFetchNew = p.getInt("fints_last_fetch_new", 0),
        )
        save(context, listOf(old))
        PinStore.adoptLegacy(context, old.id)
        p.edit().remove("fints_blz").remove("fints_kennung").remove("fints_bank_name").remove("fints_tan_medium")
            .remove("fints_last_fetch_at").remove("fints_last_fetch_new").apply()
        return listOf(old)
    }

    fun get(context: Context, id: String): BankConnection? = all(context).firstOrNull { it.id == id }

    /** Keep the bank's system id for this login (see [BankConnection.systemId]). */
    @Synchronized
    fun setSystemId(context: Context, id: String, systemId: String) {
        val c = get(context, id) ?: return
        if (c.systemId != systemId) put(context, c.copy(systemId = systemId))
    }

    /** Remember which statement format works for this bank (see [BankConnection.camt]). */
    @Synchronized
    fun setCamt(context: Context, id: String, camt: Boolean) {
        val c = get(context, id) ?: return
        if (c.camt != camt) put(context, c.copy(camt = camt))
    }

    /** Adds the connection, or replaces the one with the same id. */
    @Synchronized
    fun put(context: Context, c: BankConnection) {
        val list = all(context)
        save(context, if (list.any { it.id == c.id }) list.map { if (it.id == c.id) c else it } else list + c)
    }

    @Synchronized
    fun update(context: Context, id: String, change: (BankConnection) -> BankConnection) {
        save(context, all(context).map { if (it.id == id) change(it) else it })
    }

    @Synchronized
    fun remove(context: Context, id: String) {
        save(context, all(context).filterNot { it.id == id })
        PinStore.clear(context, id)
    }

    fun recordFetch(context: Context, id: String, imported: Int) =
        update(context, id) { it.copy(lastFetchAt = System.currentTimeMillis(), lastFetchNew = imported) }

    private fun save(context: Context, list: List<BankConnection>) {
        prefs(context).edit().putString(KEY, json.encodeToString(list)).apply()
    }
}

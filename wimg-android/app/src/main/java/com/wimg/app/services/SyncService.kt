package com.wimg.app.services


import android.content.Context
import com.wimg.app.bridge.WimgJni
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

@Serializable
private data class SyncPayload(val rows: List<SyncRow>)

@Serializable
private data class SyncRow(
    val table: String,
    val id: String,
    val data: kotlinx.serialization.json.JsonElement,
    val updated_at: Long,
)

object SyncService {
    private const val BASE_URL = "https://wimg-sync.komiljonmaksudov.com"
    private const val PREFS = "wimg"
    private const val KEY_SYNC_KEY = "wimg_sync_key"
    private const val KEY_LAST_TS = "wimg_sync_last_ts"

    private const val KEY_DEVICE_ID = "wimg_sync_device_id"
    /** Set when another device removed this one or the key was replaced. */
    const val KEY_REMOVED = "wimg_sync_removed"

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private var encryptionKey: ByteArray? = null
    private var webSocket: WebSocket? = null
    private var suppressUntil = 0L

    fun getSyncKey(context: Context): String? {
        return context.getSharedPreferences(PREFS, 0).getString(KEY_SYNC_KEY, null)
    }

    fun isEnabled(context: Context): Boolean = getSyncKey(context) != null

    /** This device's id in the device list (random, never leaves the E2E data). */
    fun deviceId(context: Context): String {
        val p = context.getSharedPreferences(PREFS, 0)
        return p.getString(KEY_DEVICE_ID, null) ?: java.util.UUID.randomUUID().toString().also { p.edit().putString(KEY_DEVICE_ID, it).apply() }
    }

    /** The name the user gave the phone (Android settings), else the model. */
    fun deviceName(context: Context): String =
        runCatching { android.provider.Settings.Global.getString(context.contentResolver, "device_name") }.getOrNull()?.takeIf { it.isNotBlank() }
            ?: android.os.Build.MODEL

    private fun deviceKind(context: Context) = if (context.resources.configuration.smallestScreenWidthDp >= 600) "tablet" else "phone"

    /** Marks this device as still linked. False: another device removed it. */
    private fun touchDevice(context: Context): Boolean {
        val body = kotlinx.serialization.json.buildJsonObject {
            put("id", kotlinx.serialization.json.JsonPrimitive(deviceId(context)))
            put("name", kotlinx.serialization.json.JsonPrimitive(deviceName(context)))
            put("kind", kotlinx.serialization.json.JsonPrimitive(deviceKind(context)))
        }.toString()
        return com.wimg.app.bridge.LibWimg.native { WimgJni.nativeTouchDevice(body) } != 1
    }

    fun wasRemoved(context: Context) = context.getSharedPreferences(PREFS, 0).getBoolean(KEY_REMOVED, false)

    /** This device is out of wimg Sync: stop, keep the data, start fresh next time. */
    private fun leaveRemoved(context: Context) {
        clearSync(context)
        context.getSharedPreferences(PREFS, 0).edit().remove(KEY_DEVICE_ID).putBoolean(KEY_REMOVED, true).apply()
    }

    /** "Alle Daten löschen": removes everything stored under this sync key on the
     *  server. True when the server confirmed it (or sync is off). */
    suspend fun deleteRemote(context: Context): Boolean = withContext(Dispatchers.IO) {
        val key = getSyncKey(context) ?: return@withContext true
        runCatching {
            client.newCall(Request.Builder().url("$BASE_URL/sync/$key").delete().build()).execute().use { it.isSuccessful }
        }.getOrDefault(false)
    }

    private const val KEY_LAST_SYNC_AT = "wimg_sync_last_ok_at"

    /** When the last successful sync finished (unix ms), or 0. */
    fun lastSyncAt(context: Context): Long = context.getSharedPreferences(PREFS, 0).getLong(KEY_LAST_SYNC_AT, 0)

    fun enableSync(context: Context): String {
        val key = java.util.UUID.randomUUID().toString()
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).remove(KEY_REMOVED).apply()
        encryptionKey = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(key) }
        return key
    }

    fun setSyncKey(context: Context, key: String) {
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).remove(KEY_REMOVED).apply()
        encryptionKey = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(key) }
    }

    fun clearSync(context: Context) {
        context.getSharedPreferences(PREFS, 0).edit()
            .remove(KEY_SYNC_KEY)
            .remove(KEY_LAST_TS)
            .remove(KEY_LAST_SYNC_AT)
            .apply()
        encryptionKey = null
        webSocket?.close(1000, null)
        webSocket = null
    }

    private fun getLastTs(context: Context): Long {
        return context.getSharedPreferences(PREFS, 0).getLong(KEY_LAST_TS, 0)
    }

    private fun setLastTs(context: Context, ts: Long) {
        context.getSharedPreferences(PREFS, 0).edit().putLong(KEY_LAST_TS, ts).apply()
    }

    /**
     * Push then pull. Never throws: a missing network or a server error comes
     * back as [SyncOutcome.error] instead of crashing the caller.
     */
    suspend fun syncNow(context: Context, onProgress: ((done: Int, total: Int) -> Unit)? = null): SyncOutcome {
        if (getSyncKey(context) == null) return SyncOutcome(0, 0, null)
        return try {
            val pushed = pushOrThrow(context)
            val pulled = pullOrThrow(context, onProgress)
            // Removed by another device (or the key was replaced): stop here.
            if (!withContext(Dispatchers.IO) { touchDevice(context) }) {
                leaveRemoved(context)
                return SyncOutcome(pushed, pulled, null, removed = true)
            }
            pushOrThrow(context) // so the others see this device
            context.getSharedPreferences(PREFS, 0).edit().putLong(KEY_LAST_SYNC_AT, System.currentTimeMillis()).apply()
            SyncOutcome(pushed, pulled, null)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.w("wimg-sync", "sync failed: ${e.javaClass.simpleName}")
            SyncOutcome(0, 0, e)
        }
    }

    /** Safe push: returns -1 on failure instead of throwing. */
    suspend fun push(context: Context): Int = safely { pushOrThrow(context) }

    /** Safe pull: returns -1 on failure instead of throwing. */
    suspend fun pull(context: Context): Int = safely { pullOrThrow(context) }

    private suspend fun safely(block: suspend () -> Int): Int = try {
        block()
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (e: Exception) {
        android.util.Log.w("wimg-sync", "sync step failed: ${e.javaClass.simpleName}")
        -1
    }

    /** Encrypts [rows] with the key of [syncKey] and posts them. */
    private fun postRows(syncKey: String, rows: List<SyncRow>): Boolean {
        val key = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(syncKey) } ?: return false
        val encryptedRows = rows.map { row ->
            val dataStr = row.data.toString()
            val nonce = ByteArray(24).also { SecureRandom().nextBytes(it) }
            val encrypted = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeEncryptField(dataStr, key, nonce) } ?: dataStr
            row.copy(data = kotlinx.serialization.json.JsonPrimitive(encrypted))
        }
        val body = json.encodeToString(SyncPayload.serializer(), SyncPayload(encryptedRows))
        val request = Request.Builder().url("$BASE_URL/sync/$syncKey").post(body.toRequestBody("application/json".toMediaType())).build()
        return client.newCall(request).execute().use { it.isSuccessful }
    }

    private suspend fun pushOrThrow(context: Context): Int = withContext(Dispatchers.IO) {
        val syncKey = getSyncKey(context) ?: return@withContext 0
        val lastTs = getLastTs(context)
        val changesJson = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeGetChanges(lastTs) } ?: return@withContext 0
        val payload = json.decodeFromString<SyncPayload>(changesJson)
        if (payload.rows.isEmpty()) return@withContext 0
        if (postRows(syncKey, payload.rows)) {
            suppressUntil = System.currentTimeMillis() + 2000
            val maxTs = payload.rows.maxOfOrNull { it.updated_at } ?: lastTs
            if (maxTs > lastTs) setLastTs(context, maxTs)
        } else throw IOException("push failed")
        payload.rows.size
    }

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    @Volatile private var firstPullRunning = false

    /**
     * The first sync after linking, with its progress docked on the bar
     * ("Daten werden geholt · 150 von 584 Umsätzen"). Runs in the app's scope,
     * so leaving the page doesn't stop it.
     */
    fun firstPull(context: Context) {
        if (firstPullRunning) return
        firstPullRunning = true
        val app = context.applicationContext
        appScope.launch {
            val row = com.wimg.app.ui.components.DockRow(com.wimg.app.ui.components.DockKind.Sync, com.wimg.app.i18n.__t("Daten werden geholt"), null, progress = 0f)
            com.wimg.app.ui.components.Dock.show(row)
            val r = syncNow(app) { done, total ->
                appScope.launch {
                    com.wimg.app.ui.components.Dock.show(row.copy(sub = com.wimg.app.i18n.__t("%d von %d Umsätzen").format(done, total), progress = if (total > 0) done.toFloat() / total else 1f))
                }
            }
            firstPullRunning = false
            if (r.error != null) com.wimg.app.ui.components.Dock.error(com.wimg.app.i18n.__t("Noch nicht synchron"), com.wimg.app.i18n.__t("Schlüssel gespeichert, aber der Server ist nicht erreichbar. wimg versucht es beim nächsten Öffnen."))
            else com.wimg.app.ui.components.Dock.info(com.wimg.app.i18n.__t("Alle Daten da"), if (r.pulled > 0) com.wimg.app.i18n.__t("%d Einträge geholt").format(r.pulled) else null)
            connectWebSocket(app, appScope)
        }
    }

    /** What a key holds on the server, read without using the key on this device. */
    sealed interface Probe {
        /** The key has data this device can read. */
        data class Found(val rows: Int) : Probe
        /** Nothing under this key, or nothing readable with it: a wrong key. */
        data object NoMatch : Probe
        data object Offline : Probe
    }

    /** Checks a key before linking ("Schlüssel passt nicht"). Never throws. */
    suspend fun probe(key: String): Probe = withContext(Dispatchers.IO) {
        runCatching {
            val body = client.newCall(Request.Builder().url("$BASE_URL/sync/$key?since=0").get().build()).execute().use {
                if (!it.isSuccessful) return@runCatching Probe.Offline
                it.body?.string() ?: ""
            }
            val rows = json.decodeFromString<SyncPayload>(body).rows
            val k = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(key) } ?: return@runCatching Probe.Offline
            // A few rows are enough to tell whether the key opens them.
            val readable = rows.take(5).count { r -> com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDecryptField(r.data.toString().trim('"'), k) } != null }
            if (rows.isEmpty() || readable == 0) Probe.NoMatch else Probe.Found(rows.size)
        }.getOrDefault(Probe.Offline)
    }

    /**
     * "Neuen Schlüssel erstellen": the other devices are removed, the server copy
     * under the old key is deleted (only the removal marks stay there, so the
     * others learn they are out), and everything goes up again under a new key.
     */
    suspend fun replaceKey(context: Context): Boolean = withContext(Dispatchers.IO) {
        val old = getSyncKey(context) ?: return@withContext false
        runCatching {
            val me = deviceId(context)
            com.wimg.app.bridge.LibWimg.getDevices().filter { it.id != me }.forEach { com.wimg.app.bridge.LibWimg.removeDevice(it.id) }
            pushOrThrow(context)
            val deleted = client.newCall(Request.Builder().url("$BASE_URL/sync/$old").delete().build()).execute().use { it.isSuccessful }
            if (!deleted) return@runCatching false
            val all = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeGetChanges(0) }?.let { json.decodeFromString<SyncPayload>(it).rows }.orEmpty()
            postRows(old, all.filter { it.table == "sync_devices" })
            webSocket?.close(1000, null)
            webSocket = null
            setSyncKey(context, java.util.UUID.randomUUID().toString())
            setLastTs(context, 0)
            pushOrThrow(context)
            context.getSharedPreferences(PREFS, 0).edit().putLong(KEY_LAST_SYNC_AT, System.currentTimeMillis()).apply()
            true
        }.getOrDefault(false)
    }

    private suspend fun pullOrThrow(context: Context, onProgress: ((Int, Int) -> Unit)? = null): Int = withContext(Dispatchers.IO) {
        val syncKey = getSyncKey(context) ?: return@withContext 0
        val lastTs = getLastTs(context)
        val key = encryptionKey ?: com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(syncKey) }.also { encryptionKey = it } ?: return@withContext 0

        val request = Request.Builder()
            .url("$BASE_URL/sync/$syncKey?since=$lastTs")
            .get()
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) { response.close(); return@withContext 0 }

        val responseBody = response.body?.string() ?: return@withContext 0
        response.close()

        val payload = json.decodeFromString<SyncPayload>(responseBody)
        if (payload.rows.isEmpty()) return@withContext 0

        // Decrypt rows
        // Rows this key can't open are skipped, never applied as they are.
        val decryptedRows = payload.rows.mapNotNull { row ->
            val dataStr = row.data.toString().trim('"')
            com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDecryptField(dataStr, key) }?.let { row.copy(data = json.parseToJsonElement(it)) }
        }

        // In batches, so a first full pull can show how far it is ("150 von 584 Umsätzen").
        val txTotal = decryptedRows.count { it.table == "transactions" }
        var txDone = 0
        var applied = 0
        decryptedRows.chunked(if (onProgress == null) Int.MAX_VALUE else 100).forEach { batch ->
            val batchJson = json.encodeToString(SyncPayload.serializer(), SyncPayload(batch))
            applied += com.wimg.app.bridge.LibWimg.native { WimgJni.nativeApplyChanges(batchJson) }.coerceAtLeast(0)
            txDone += batch.count { it.table == "transactions" }
            onProgress?.invoke(txDone, txTotal)
        }
        if (applied > 0) {
            val maxTs = payload.rows.maxOfOrNull { it.updated_at } ?: lastTs
            if (maxTs > lastTs) setLastTs(context, maxTs)
            WidgetDataWriter.writeSummary(context)
            com.wimg.app.ui.components.Changes.bump()
        }
        applied
    }

    /** Closes the live connection (app going to the background). */
    fun disconnectWebSocket() {
        wsWanted = false
        webSocket?.close(1000, null)
        webSocket = null
    }

    @Volatile private var wsWanted = false

    fun connectWebSocket(context: Context, scope: CoroutineScope) {
        val syncKey = getSyncKey(context) ?: return
        wsWanted = true
        if (webSocket != null) return
        val wsUrl = BASE_URL.replace("https://", "wss://").replace("http://", "ws://")

        val request = Request.Builder().url("$wsUrl/ws/$syncKey").build()
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (System.currentTimeMillis() < suppressUntil) return
                scope.launch { pull(context) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                SyncService.webSocket = null
                // Reconnect after a delay, but only while the app wants a connection.
                scope.launch {
                    delay(5000)
                    if (wsWanted) connectWebSocket(context, scope)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                SyncService.webSocket = null
            }
        })
    }
}

data class SyncOutcome(val pushed: Int, val pulled: Int, val error: Throwable?, val removed: Boolean = false)

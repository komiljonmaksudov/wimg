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
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).apply()
        encryptionKey = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(key) }
        return key
    }

    fun setSyncKey(context: Context, key: String) {
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).apply()
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
    suspend fun syncNow(context: Context): SyncOutcome {
        if (getSyncKey(context) == null) return SyncOutcome(0, 0, null)
        return try {
            val pushed = pushOrThrow(context)
            val pulled = pullOrThrow(context)
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

    private suspend fun pushOrThrow(context: Context): Int = withContext(Dispatchers.IO) {
        val syncKey = getSyncKey(context) ?: return@withContext 0
        val lastTs = getLastTs(context)
        val changesJson = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeGetChanges(lastTs) } ?: return@withContext 0

        val key = encryptionKey ?: com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDeriveKey(syncKey) }.also { encryptionKey = it } ?: return@withContext 0

        // Encrypt rows
        val payload = json.decodeFromString<SyncPayload>(changesJson)
        if (payload.rows.isEmpty()) return@withContext 0

        val encryptedRows = payload.rows.map { row ->
            val dataStr = row.data.toString()
            val nonce = ByteArray(24).also { SecureRandom().nextBytes(it) }
            val encrypted = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeEncryptField(dataStr, key, nonce) } ?: dataStr
            row.copy(data = kotlinx.serialization.json.JsonPrimitive(encrypted))
        }

        val body = json.encodeToString(SyncPayload.serializer(), SyncPayload(encryptedRows))
        val request = Request.Builder()
            .url("$BASE_URL/sync/$syncKey")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        val response = client.newCall(request).execute()
        if (response.isSuccessful) {
            suppressUntil = System.currentTimeMillis() + 2000
            val maxTs = payload.rows.maxOfOrNull { it.updated_at } ?: lastTs
            if (maxTs > lastTs) setLastTs(context, maxTs)
        }
        response.close()
        payload.rows.size
    }

    private suspend fun pullOrThrow(context: Context): Int = withContext(Dispatchers.IO) {
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
        val decryptedRows = payload.rows.map { row ->
            val dataStr = row.data.toString().trim('"')
            val decrypted = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeDecryptField(dataStr, key) }
            if (decrypted != null) {
                row.copy(data = json.parseToJsonElement(decrypted))
            } else {
                row
            }
        }

        val decryptedJson = json.encodeToString(SyncPayload.serializer(), SyncPayload(decryptedRows))
        val applied = com.wimg.app.bridge.LibWimg.native { WimgJni.nativeApplyChanges(decryptedJson) }
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

data class SyncOutcome(val pushed: Int, val pulled: Int, val error: Throwable?)

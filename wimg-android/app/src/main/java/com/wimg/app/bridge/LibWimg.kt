package com.wimg.app.bridge

import android.content.Context
import com.wimg.app.models.*
import kotlinx.serialization.json.Json
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * High-level Kotlin wrapper over libwimg C ABI via JNI.
 * Mirrors iOS LibWimg.swift — thread-safe singleton.
 */
object LibWimg {
    private val lock = WatchedLock()

    /**
     * libwimg is single-threaded (one SQLite connection, one shared result
     * buffer). Every call into it — sync, bank, backup included — goes through
     * this lock, or two threads overwrite each other's results.
     */
    fun <T> native(block: () -> T): T = lock.withLock(block)

    fun fintsFetch(body: String): String? = native { WimgJni.nativeFintsFetch(body) }

    /** For reads on the main thread: runs [block] only if libwimg is free right
     *  now (a bank fetch can hold it for seconds), else returns null. */
    fun <T> ifFree(block: () -> T): T? {
        if (!lock.tryLock()) return null
        return try { block() } finally { lock.unlock() }
    }
    private val json = Json { ignoreUnknownKeys = true }
    private var initialized = false

    fun initialize(context: Context) = lock.withLock {
        val dbPath = File(context.filesDir, "wimg.db").absolutePath
        val rc = WimgJni.nativeInit(dbPath)
        if (rc != 0) {
            throw WimgException("Init failed: ${WimgJni.nativeGetError() ?: "unknown"}")
        }
        initialized = true
    }

    fun close() = lock.withLock {
        WimgJni.nativeClose()
        initialized = false
    }

    // --- Transactions ---

    fun getTransactions(): List<Transaction> = lock.withLock {
        val str = WimgJni.nativeGetTransactions() ?: return emptyList()
        json.decodeFromString(str)
    }

    fun getTransactionsFiltered(account: String?): List<Transaction> = lock.withLock {
        val str = WimgJni.nativeGetTransactionsFiltered(account ?: "") ?: return emptyList()
        json.decodeFromString(str)
    }

    /** Not yet booked ("vorgemerkt"), from the last bank fetch. Never counted in totals. */
    fun getPending(account: String?): List<Transaction> = lock.withLock {
        val str = WimgJni.nativeGetPending(account ?: "") ?: return emptyList()
        runCatching { json.decodeFromString<List<Transaction>>(str) }.getOrDefault(emptyList())
    }

    fun setCategory(id: String, category: Int) = lock.withLock {
        val rc = WimgJni.nativeSetCategory(id, category)
        if (rc != 0) throw WimgException("setCategory failed")
    }

    fun setExcluded(id: String, excluded: Boolean) = lock.withLock {
        val rc = WimgJni.nativeSetExcluded(id, if (excluded) 1 else 0)
        if (rc != 0) throw WimgException("setExcluded failed")
    }

    fun autoCategorize(): Int = lock.withLock {
        WimgJni.nativeAutoCategorize()
    }

    // --- Summaries ---

    fun getSummaryFiltered(year: Int, month: Int, account: String?): MonthlySummary? = lock.withLock {
        val str = WimgJni.nativeGetSummaryFiltered(year, month, account ?: "") ?: return null
        json.decodeFromString(str)
    }

    // --- Import ---

    fun parseCsv(data: ByteArray): ParseResult? = lock.withLock {
        val str = WimgJni.nativeParseCsv(data) ?: return null
        json.decodeFromString(str)
    }

    fun importCsv(data: ByteArray): ImportResult? = lock.withLock {
        val str = WimgJni.nativeImportCsv(data) ?: return null
        json.decodeFromString(str)
    }

    // --- Accounts ---

    fun getAccounts(): List<Account> = lock.withLock {
        val str = WimgJni.nativeGetAccounts() ?: return emptyList()
        json.decodeFromString(str)
    }

    fun setAccountHidden(id: String, hidden: Boolean) = lock.withLock { WimgJni.nativeSetAccountHidden(id, if (hidden) 1 else 0) == 0 }

    /** "Name in wimg": the bank's id stays, only the shown name changes. */
    fun renameAccount(account: Account, name: String) = lock.withLock {
        val body = kotlinx.serialization.json.buildJsonObject {
            put("id", kotlinx.serialization.json.JsonPrimitive(account.id))
            put("name", kotlinx.serialization.json.JsonPrimitive(name))
            put("color", kotlinx.serialization.json.JsonPrimitive(account.color))
        }.toString()
        WimgJni.nativeUpdateAccount(body) == 0
    }

    // --- Gehaltsmonat ---

    private fun ymd(iso: String) = iso.replace("-", "").toInt()

    /** Periods (newest first) as of today. */
    fun getPeriods(count: Int = 12): Periods? = lock.withLock {
        val today = java.util.Calendar.getInstance().let { it.get(java.util.Calendar.YEAR) * 10000 + (it.get(java.util.Calendar.MONTH) + 1) * 100 + it.get(java.util.Calendar.DAY_OF_MONTH) }
        val str = WimgJni.nativeGetPeriods(today, count) ?: return null
        runCatching { json.decodeFromString<Periods>(str) }.getOrNull()
    }

    /** Summary of [from]..[to] (ISO dates, inclusive). */
    fun getSummaryRange(from: String, to: String, account: String?): MonthlySummary? = lock.withLock {
        val str = WimgJni.nativeGetSummaryRange(ymd(from), ymd(to), account ?: "") ?: return null
        json.decodeFromString(str)
    }

    /** "calendar", "salary" or "day" (with the start [day]). */
    fun setPeriodMode(mode: String, day: Int = 0) = lock.withLock { WimgJni.nativeSetPeriodMode(mode, day) == 0 }

    /** 1 = this is my salary, 0 = it isn't, 2 = only this payer. */
    fun answerSalary(key: String, answer: Int) = lock.withLock { WimgJni.nativeSalaryAnswer(key, answer) == 0 }

    // --- wimg Sync devices ---

    fun getDevices(): List<SyncDevice> = lock.withLock {
        val str = WimgJni.nativeGetDevices() ?: return emptyList()
        runCatching { json.decodeFromString<List<SyncDevice>>(str) }.getOrDefault(emptyList())
    }

    fun removeDevice(id: String) = lock.withLock { WimgJni.nativeRemoveDevice(id) == 0 }

    // --- Recurring ---

    fun getRules(): List<Rule> = lock.withLock {
        val str = WimgJni.nativeGetRules() ?: return emptyList()
        json.decodeFromString(str)
    }

    fun deleteRule(id: Long, reset: Boolean): Boolean = lock.withLock { WimgJni.nativeDeleteRule(id, if (reset) 1 else 0) == 0 }

    /** A transaction entered by hand; [date] "YYYY-MM-DD", amount signed in cents. */
    fun addManualTransaction(date: String, description: String, amountCents: Long, category: Int, account: String): Boolean =
        lock.withLock { WimgJni.nativeAddManualTransaction(date, description, amountCents, category, account) == 0 }

    /** "Nicht wiederkehrend" / "Wieder anzeigen". */
    fun setRecurringHidden(id: String, hidden: Boolean) = lock.withLock { WimgJni.nativeSetRecurringHidden(id, if (hidden) 1 else 0) == 0 }

    /** Edit panel; null/blank = as detected, [fixedCents] null = automatic amount. */
    fun editRecurring(id: String, name: String?, category: Int?, interval: String?, fixedCents: Long?) = lock.withLock {
        WimgJni.nativeEditRecurring(id, name.orEmpty(), category ?: -1, interval.orEmpty(), fixedCents ?: Long.MIN_VALUE) == 0
    }

    /** "Stimmt, neuer Preis". */
    fun acceptRecurringPrice(id: String) = lock.withLock { WimgJni.nativeAcceptRecurringPrice(id) == 0 }

    /** "Einmalige Zahlung" (true) or "gehört dazu" (false); detection runs again. */
    fun setRecurringOneoff(patternId: String, txId: String, oneoff: Boolean) = lock.withLock {
        val ok = WimgJni.nativeSetRecurringOneoff(patternId, txId, if (oneoff) 1 else 0) == 0
        WimgJni.nativeDetectRecurring()
        ok
    }

    fun getRecurring(): List<RecurringPattern> = lock.withLock {
        val str = WimgJni.nativeGetRecurring() ?: return emptyList()
        json.decodeFromString(str)
    }

    fun detectRecurring(): Int = lock.withLock {
        WimgJni.nativeDetectRecurring()
    }

    /** Payments that belong to a recurring pattern, newest first. */
    fun getRecurringPayments(id: String): List<RecurringPayment> = lock.withLock {
        val str = WimgJni.nativeGetRecurringPayments(id) ?: return emptyList()
        json.decodeFromString(str)
    }

    // --- Snapshots ---

    // --- Undo/Redo ---

    fun undo(): UndoResult? = lock.withLock {
        val str = WimgJni.nativeUndo() ?: return null
        json.decodeFromString(str)
    }

}

class WimgException(message: String) : Exception(message)


/**
 * libwimg's one lock. With FrameWatch on it reports every main-thread call that
 * costs more than a frame (waiting for a bank fetch or sync, or running long):
 * those are the hitches when switching pages. Tag "wimg-jank".
 */
internal class WatchedLock {
    private val inner = ReentrantLock()

    inline fun <T> withLock(block: () -> T): T {
        if (!com.wimg.app.FrameWatch.enabled || android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) return withLockPlain(block)
        val t0 = System.nanoTime()
        lockPlain()
        val t1 = System.nanoTime()
        try { return block() } finally {
            unlockPlain()
            val waitMs = (t1 - t0) / 1_000_000
            val runMs = (System.nanoTime() - t1) / 1_000_000
            if (waitMs + runMs >= 8) {
                val at = Throwable().stackTrace.firstOrNull { it.className.startsWith("com.wimg.app") && !it.className.startsWith("com.wimg.app.bridge") }
                android.util.Log.w("wimg-jank", "main thread: waited ${waitMs} ms, ran ${runMs} ms at ${at?.className?.substringAfterLast('.')}.${at?.methodName}:${at?.lineNumber}")
            }
        }
    }

    inline fun <T> withLockPlain(block: () -> T): T { lockPlain(); try { return block() } finally { unlockPlain() } }
    fun lockPlain() = inner.lock()
    fun unlockPlain() = inner.unlock()
    fun tryLock() = inner.tryLock()
    fun unlock() = inner.unlock()
}

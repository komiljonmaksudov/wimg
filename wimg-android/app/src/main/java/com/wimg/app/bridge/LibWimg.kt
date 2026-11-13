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
    private val lock = ReentrantLock()

    /**
     * libwimg is single-threaded (one SQLite connection, one shared result
     * buffer). Every call into it — sync, bank, backup included — goes through
     * this lock, or two threads overwrite each other's results.
     */
    fun <T> native(block: () -> T): T = lock.withLock(block)

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

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

    fun getSummary(year: Int, month: Int): MonthlySummary? = lock.withLock {
        val str = WimgJni.nativeGetSummary(year, month) ?: return null
        json.decodeFromString(str)
    }

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

    fun takeSnapshot(year: Int, month: Int) = lock.withLock {
        val rc = WimgJni.nativeTakeSnapshot(year, month)
        if (rc != 0) throw WimgException("takeSnapshot failed")
    }

    fun getSnapshots(): List<Snapshot> = lock.withLock {
        val str = WimgJni.nativeGetSnapshots() ?: return emptyList()
        json.decodeFromString(str)
    }

    // --- Undo/Redo ---

    fun undo(): UndoResult? = lock.withLock {
        val str = WimgJni.nativeUndo() ?: return null
        json.decodeFromString(str)
    }

    fun redo(): UndoResult? = lock.withLock {
        val str = WimgJni.nativeRedo() ?: return null
        json.decodeFromString(str)
    }
}

class WimgException(message: String) : Exception(message)

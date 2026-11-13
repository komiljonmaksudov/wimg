package com.wimg.app.bridge

/**
 * Raw JNI declarations mapping to wimg_jni.c native methods.
 * Each function corresponds to a C ABI function in libwimg.
 */
object WimgJni {
    init {
        System.loadLibrary("wimg")
        System.loadLibrary("wimg-jni")
    }

    // Lifecycle
    external fun nativeInit(dbPath: String): Int
    external fun nativeClose()
    external fun nativeGetError(): String?

    // Transactions
    external fun nativeGetTransactions(): String?
    external fun nativeGetTransactionsFiltered(account: String): String?
    external fun nativeGetPending(account: String): String?
    external fun nativeSetCategory(id: String, category: Int): Int
    external fun nativeSetExcluded(id: String, excluded: Int): Int
    external fun nativeAutoCategorize(): Int

    // Summaries
    external fun nativeGetSummaryFiltered(year: Int, month: Int, account: String): String?

    // Import
    external fun nativeParseCsv(data: ByteArray): String?
    external fun nativeImportCsv(data: ByteArray): String?

    // Accounts
    external fun nativeGetAccounts(): String?

    // Recurring
    external fun nativeGetRecurring(): String?
    external fun nativeDetectRecurring(): Int
    external fun nativeGetRecurringPayments(id: String): String?

    // Snapshots

    // Undo/Redo
    external fun nativeUndo(): String?

    // Debts

    // Goals

    // Export
    external fun nativeExportCsv(): String?

    // Sync
    external fun nativeGetChanges(sinceTs: Long): String?
    external fun nativeApplyChanges(json: String): Int
    external fun nativeDeriveKey(syncKey: String): ByteArray?
    external fun nativeEncryptField(plaintext: String, key: ByteArray, nonce: ByteArray): String?
    external fun nativeDecryptField(ciphertext: String, key: ByteArray): String?

    // FinTS
    external fun nativeSetHttpCallback(callback: Any)
    external fun nativeFintsConnect(json: String): String?
    external fun nativeFintsSendTan(json: String): String?
    external fun nativeFintsFetch(json: String): String?
    external fun nativeFintsGetBanks(): String?
    external fun nativeFintsGetTanMedia(): String?
    external fun nativeFintsSetTanMedium(json: String): String?

    // Rules + manual entries
    external fun nativeGetRules(): String?
    external fun nativeDeleteRule(id: Long, reset: Int): Int
    external fun nativeAddManualTransaction(date: String, description: String, amountCents: Long, category: Int, account: String): Int
}

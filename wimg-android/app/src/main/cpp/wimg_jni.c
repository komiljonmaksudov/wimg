#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// libwimg C ABI declarations (matches libwimg.h)
extern int32_t wimg_init(const char *db_path);
extern void wimg_close(void);
extern void wimg_free(const uint8_t *ptr, uint32_t len);
extern const uint8_t *wimg_get_error(void);
extern const uint8_t *wimg_get_transactions(void);
extern const uint8_t *wimg_get_transactions_filtered(const uint8_t *acct, uint32_t acct_len);
extern const uint8_t *wimg_get_pending(const uint8_t *acct, uint32_t acct_len);
extern int32_t wimg_set_category(const uint8_t *id, uint32_t id_len, uint8_t category);
extern int32_t wimg_set_excluded(const uint8_t *id, uint32_t id_len, uint8_t excluded);
extern int32_t wimg_auto_categorize(void);
extern const uint8_t *wimg_get_summary_filtered(uint32_t year, uint32_t month, const uint8_t *acct, uint32_t acct_len);
extern const uint8_t *wimg_parse_csv(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_import_csv(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_get_accounts(void);
extern const uint8_t *wimg_get_recurring(void);
extern int32_t wimg_detect_recurring(void);
extern const uint8_t *wimg_get_recurring_payments(const uint8_t *id, uint32_t id_len);
extern const uint8_t *wimg_undo(void);
extern const uint8_t *wimg_get_rules(void);
extern const uint8_t *wimg_get_periods(uint32_t today_ymd, uint32_t count);
extern const uint8_t *wimg_get_summary_range(uint32_t from_ymd, uint32_t to_ymd, const uint8_t *acct, uint32_t acct_len);
extern int32_t wimg_set_period_mode(const uint8_t *mode, uint32_t mode_len, uint32_t day);
extern int32_t wimg_salary_answer(const uint8_t *key, uint32_t key_len, uint8_t answer);
extern int32_t wimg_touch_device(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_get_devices(void);
extern int32_t wimg_remove_device(const uint8_t *id, uint32_t id_len);
extern int32_t wimg_set_account_hidden(const uint8_t *id, uint32_t id_len, uint8_t hidden);
extern int32_t wimg_update_account(const uint8_t *data, uint32_t len);
extern int32_t wimg_set_recurring_hidden(const uint8_t *id, uint32_t id_len, uint8_t hidden);
extern int32_t wimg_edit_recurring(const uint8_t *id, uint32_t id_len, const uint8_t *name, uint32_t name_len, int32_t category, const uint8_t *interval, uint32_t interval_len, int64_t fixed_cents);
extern int32_t wimg_accept_recurring_price(const uint8_t *id, uint32_t id_len);
extern int32_t wimg_set_recurring_oneoff(const uint8_t *pid, uint32_t pid_len, const uint8_t *tid, uint32_t tid_len, uint8_t oneoff);
extern int32_t wimg_delete_rule(int64_t id, uint8_t reset);
extern int32_t wimg_add_manual_transaction(const uint8_t *date, uint32_t date_len, const uint8_t *desc, uint32_t desc_len, int64_t amount_cents, uint8_t category, const uint8_t *acct, uint32_t acct_len);
extern const uint8_t *wimg_export_csv(void);

// Sync
extern const uint8_t *wimg_get_changes(int64_t since_ts);
extern int32_t wimg_apply_changes(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_derive_key(const uint8_t *sync_key, uint32_t sync_key_len);
extern const uint8_t *wimg_encrypt_field(const uint8_t *plaintext, uint32_t plaintext_len,
                                         const uint8_t *key, const uint8_t *nonce);
extern const uint8_t *wimg_decrypt_field(const uint8_t *ciphertext, uint32_t ciphertext_len,
                                         const uint8_t *key);

// FinTS
typedef int32_t (*wimg_http_callback_t)(const uint8_t *url, uint32_t url_len,
                                        const uint8_t *body, uint32_t body_len,
                                        uint8_t *out, uint32_t out_len);
extern void wimg_set_http_callback(wimg_http_callback_t callback);
extern const uint8_t *wimg_fints_connect(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_fints_send_tan(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_fints_fetch(const uint8_t *data, uint32_t len);
extern const uint8_t *wimg_fints_get_banks(void);
extern const uint8_t *wimg_fints_get_tan_media(void);
extern const uint8_t *wimg_fints_set_tan_medium(const uint8_t *data, uint32_t len);

// Helper: read 4-byte LE length-prefixed data and create a Java string, then free
static jstring ptr_to_jstring(JNIEnv *env, const uint8_t *ptr) {
    if (!ptr) return NULL;
    uint32_t len = ptr[0] | (ptr[1] << 8) | (ptr[2] << 16) | (ptr[3] << 24);
    if (len == 0) { wimg_free(ptr, 0); return NULL; }
    // Create a null-terminated copy for NewStringUTF
    char *buf = malloc(len + 1);
    memcpy(buf, ptr + 4, len);
    buf[len] = '\0';
    wimg_free(ptr, 0);
    jstring result = (*env)->NewStringUTF(env, buf);
    free(buf);
    return result;
}

#define JNI_FN(name) Java_com_wimg_app_bridge_WimgJni_##name

// --- Lifecycle ---

JNIEXPORT jint JNICALL JNI_FN(nativeInit)(JNIEnv *env, jobject obj, jstring path) {
    const char *db_path = (*env)->GetStringUTFChars(env, path, NULL);
    int32_t rc = wimg_init(db_path);
    (*env)->ReleaseStringUTFChars(env, path, db_path);
    return rc;
}

JNIEXPORT void JNICALL JNI_FN(nativeClose)(JNIEnv *env, jobject obj) {
    wimg_close();
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetError)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_error());
}

// --- Transactions ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetTransactions)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_transactions());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetTransactionsFiltered)(JNIEnv *env, jobject obj, jstring acct) {
    const char *a = (*env)->GetStringUTFChars(env, acct, NULL);
    jsize alen = (*env)->GetStringUTFLength(env, acct);
    const uint8_t *ptr = wimg_get_transactions_filtered((const uint8_t *)a, alen);
    (*env)->ReleaseStringUTFChars(env, acct, a);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetPending)(JNIEnv *env, jobject obj, jstring acct) {
    const char *a = (*env)->GetStringUTFChars(env, acct, NULL);
    jsize alen = (*env)->GetStringUTFLength(env, acct);
    const uint8_t *ptr = wimg_get_pending((const uint8_t *)a, alen);
    (*env)->ReleaseStringUTFChars(env, acct, a);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetCategory)(JNIEnv *env, jobject obj, jstring id, jint category) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_set_category((const uint8_t *)cid, len, (uint8_t)category);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetExcluded)(JNIEnv *env, jobject obj, jstring id, jint excluded) {
    const char *cid = (*env)->GetStringUTFChars(env, id, NULL);
    jsize len = (*env)->GetStringUTFLength(env, id);
    int32_t rc = wimg_set_excluded((const uint8_t *)cid, len, (uint8_t)excluded);
    (*env)->ReleaseStringUTFChars(env, id, cid);
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeAutoCategorize)(JNIEnv *env, jobject obj) {
    return wimg_auto_categorize();
}

// --- Summaries ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetSummaryFiltered)(JNIEnv *env, jobject obj, jint year, jint month, jstring acct) {
    const char *a = (*env)->GetStringUTFChars(env, acct, NULL);
    jsize alen = (*env)->GetStringUTFLength(env, acct);
    const uint8_t *ptr = wimg_get_summary_filtered(year, month, (const uint8_t *)a, alen);
    (*env)->ReleaseStringUTFChars(env, acct, a);
    return ptr_to_jstring(env, ptr);
}

// --- Import ---

JNIEXPORT jstring JNICALL JNI_FN(nativeParseCsv)(JNIEnv *env, jobject obj, jbyteArray data) {
    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    const uint8_t *ptr = wimg_parse_csv((const uint8_t *)bytes, len);
    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeImportCsv)(JNIEnv *env, jobject obj, jbyteArray data) {
    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    const uint8_t *ptr = wimg_import_csv((const uint8_t *)bytes, len);
    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

// --- Recurring: user decisions ---

#define WITH_UTF(js, var, len) const char *var = (*env)->GetStringUTFChars(env, js, NULL); jsize len = (*env)->GetStringUTFLength(env, js);
#define END_UTF(js, var) (*env)->ReleaseStringUTFChars(env, js, var);

JNIEXPORT jstring JNICALL JNI_FN(nativeGetPeriods)(JNIEnv *env, jobject obj, jint today, jint count) {
    return ptr_to_jstring(env, wimg_get_periods((uint32_t)today, (uint32_t)count));
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetSummaryRange)(JNIEnv *env, jobject obj, jint from, jint to, jstring acct) {
    WITH_UTF(acct, c, n)
    const uint8_t *ptr = wimg_get_summary_range((uint32_t)from, (uint32_t)to, (const uint8_t *)c, n);
    END_UTF(acct, c)
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetPeriodMode)(JNIEnv *env, jobject obj, jstring mode, jint day) {
    WITH_UTF(mode, c, n)
    int32_t rc = wimg_set_period_mode((const uint8_t *)c, n, (uint32_t)day);
    END_UTF(mode, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSalaryAnswer)(JNIEnv *env, jobject obj, jstring key, jint answer) {
    WITH_UTF(key, c, n)
    int32_t rc = wimg_salary_answer((const uint8_t *)c, n, (uint8_t)answer);
    END_UTF(key, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeTouchDevice)(JNIEnv *env, jobject obj, jstring json) {
    WITH_UTF(json, c, n)
    int32_t rc = wimg_touch_device((const uint8_t *)c, n);
    END_UTF(json, c)
    return rc;
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetDevices)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_devices());
}

JNIEXPORT jint JNICALL JNI_FN(nativeRemoveDevice)(JNIEnv *env, jobject obj, jstring id) {
    WITH_UTF(id, c, n)
    int32_t rc = wimg_remove_device((const uint8_t *)c, n);
    END_UTF(id, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetAccountHidden)(JNIEnv *env, jobject obj, jstring id, jint hidden) {
    WITH_UTF(id, c, n)
    int32_t rc = wimg_set_account_hidden((const uint8_t *)c, n, (uint8_t)hidden);
    END_UTF(id, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeUpdateAccount)(JNIEnv *env, jobject obj, jstring json) {
    WITH_UTF(json, c, n)
    int32_t rc = wimg_update_account((const uint8_t *)c, n);
    END_UTF(json, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetRecurringHidden)(JNIEnv *env, jobject obj, jstring id, jint hidden) {
    WITH_UTF(id, c, n)
    int32_t rc = wimg_set_recurring_hidden((const uint8_t *)c, n, (uint8_t)hidden);
    END_UTF(id, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeEditRecurring)(JNIEnv *env, jobject obj, jstring id, jstring name, jint category, jstring interval, jlong fixed) {
    WITH_UTF(id, ci, ni)
    WITH_UTF(name, cn, nn)
    WITH_UTF(interval, cv, nv)
    int32_t rc = wimg_edit_recurring((const uint8_t *)ci, ni, (const uint8_t *)cn, nn, (int32_t)category, (const uint8_t *)cv, nv, (int64_t)fixed);
    END_UTF(id, ci) END_UTF(name, cn) END_UTF(interval, cv)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeAcceptRecurringPrice)(JNIEnv *env, jobject obj, jstring id) {
    WITH_UTF(id, c, n)
    int32_t rc = wimg_accept_recurring_price((const uint8_t *)c, n);
    END_UTF(id, c)
    return rc;
}

JNIEXPORT jint JNICALL JNI_FN(nativeSetRecurringOneoff)(JNIEnv *env, jobject obj, jstring pid, jstring tid, jint oneoff) {
    WITH_UTF(pid, cp, np)
    WITH_UTF(tid, ct, nt)
    int32_t rc = wimg_set_recurring_oneoff((const uint8_t *)cp, np, (const uint8_t *)ct, nt, (uint8_t)oneoff);
    END_UTF(pid, cp) END_UTF(tid, ct)
    return rc;
}

// --- Rules + manual entries ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetRules)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_rules());
}

JNIEXPORT jint JNICALL JNI_FN(nativeDeleteRule)(JNIEnv *env, jobject obj, jlong id, jint reset) {
    return wimg_delete_rule((int64_t)id, (uint8_t)reset);
}

JNIEXPORT jint JNICALL JNI_FN(nativeAddManualTransaction)(JNIEnv *env, jobject obj, jstring date, jstring desc, jlong amount, jint category, jstring acct) {
    const char *cd = (*env)->GetStringUTFChars(env, date, NULL);
    const char *cs = (*env)->GetStringUTFChars(env, desc, NULL);
    const char *ca = (*env)->GetStringUTFChars(env, acct, NULL);
    int32_t rc = wimg_add_manual_transaction((const uint8_t *)cd, (*env)->GetStringUTFLength(env, date),
        (const uint8_t *)cs, (*env)->GetStringUTFLength(env, desc), (int64_t)amount, (uint8_t)category,
        (const uint8_t *)ca, (*env)->GetStringUTFLength(env, acct));
    (*env)->ReleaseStringUTFChars(env, date, cd);
    (*env)->ReleaseStringUTFChars(env, desc, cs);
    (*env)->ReleaseStringUTFChars(env, acct, ca);
    return rc;
}

// --- Accounts ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetAccounts)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_accounts());
}

// --- Recurring ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetRecurring)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_get_recurring());
}

JNIEXPORT jint JNICALL JNI_FN(nativeDetectRecurring)(JNIEnv *env, jobject obj) {
    return wimg_detect_recurring();
}

JNIEXPORT jstring JNICALL JNI_FN(nativeGetRecurringPayments)(JNIEnv *env, jobject obj, jstring id) {
    const char *s = (*env)->GetStringUTFChars(env, id, NULL);
    if (s == NULL) return NULL;
    jsize len = (*env)->GetStringUTFLength(env, id);
    const uint8_t *res = wimg_get_recurring_payments((const uint8_t *)s, (uint32_t)len);
    (*env)->ReleaseStringUTFChars(env, id, s);
    return ptr_to_jstring(env, res);
}

// --- Snapshots ---

// --- Undo/Redo ---

JNIEXPORT jstring JNICALL JNI_FN(nativeUndo)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_undo());
}

// --- Debts ---

// --- Goals ---

// --- Export ---

JNIEXPORT jstring JNICALL JNI_FN(nativeExportCsv)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_export_csv());
}

// --- Sync ---

JNIEXPORT jstring JNICALL JNI_FN(nativeGetChanges)(JNIEnv *env, jobject obj, jlong sinceTs) {
    return ptr_to_jstring(env, wimg_get_changes(sinceTs));
}

JNIEXPORT jint JNICALL JNI_FN(nativeApplyChanges)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    int32_t rc = wimg_apply_changes((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return rc;
}

JNIEXPORT jbyteArray JNICALL JNI_FN(nativeDeriveKey)(JNIEnv *env, jobject obj, jstring syncKey) {
    const char *key = (*env)->GetStringUTFChars(env, syncKey, NULL);
    jsize len = (*env)->GetStringUTFLength(env, syncKey);
    const uint8_t *ptr = wimg_derive_key((const uint8_t *)key, len);
    (*env)->ReleaseStringUTFChars(env, syncKey, key);
    if (!ptr) return NULL;
    uint32_t dlen = ptr[0] | (ptr[1] << 8) | (ptr[2] << 16) | (ptr[3] << 24);
    jbyteArray result = (*env)->NewByteArray(env, dlen);
    (*env)->SetByteArrayRegion(env, result, 0, dlen, (const jbyte *)(ptr + 4));
    wimg_free(ptr, 0);
    return result;
}

JNIEXPORT jstring JNICALL JNI_FN(nativeEncryptField)(JNIEnv *env, jobject obj, jstring plaintext, jbyteArray key, jbyteArray nonce) {
    const char *pt = (*env)->GetStringUTFChars(env, plaintext, NULL);
    jsize pt_len = (*env)->GetStringUTFLength(env, plaintext);
    jbyte *k = (*env)->GetByteArrayElements(env, key, NULL);
    jbyte *n = (*env)->GetByteArrayElements(env, nonce, NULL);
    const uint8_t *ptr = wimg_encrypt_field((const uint8_t *)pt, pt_len, (const uint8_t *)k, (const uint8_t *)n);
    (*env)->ReleaseStringUTFChars(env, plaintext, pt);
    (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, nonce, n, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeDecryptField)(JNIEnv *env, jobject obj, jstring ciphertext, jbyteArray key) {
    const char *ct = (*env)->GetStringUTFChars(env, ciphertext, NULL);
    jsize ct_len = (*env)->GetStringUTFLength(env, ciphertext);
    jbyte *k = (*env)->GetByteArrayElements(env, key, NULL);
    const uint8_t *ptr = wimg_decrypt_field((const uint8_t *)ct, ct_len, (const uint8_t *)k);
    (*env)->ReleaseStringUTFChars(env, ciphertext, ct);
    (*env)->ReleaseByteArrayElements(env, key, k, JNI_ABORT);
    return ptr_to_jstring(env, ptr);
}

// --- FinTS ---

// Global references for HTTP callback
static JavaVM *g_jvm = NULL;
static jobject g_http_callback = NULL;
static jmethodID g_http_method = NULL;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

static int32_t jni_http_callback(const uint8_t *url, uint32_t url_len,
                                  const uint8_t *body, uint32_t body_len,
                                  uint8_t *out, uint32_t out_len) {
    if (!g_jvm || !g_http_callback) return -1;

    JNIEnv *env;
    int attached = 0;
    if ((*g_jvm)->GetEnv(g_jvm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != JNI_OK) return -1;
        attached = 1;
    }

    // Create URL string
    char *url_buf = malloc(url_len + 1);
    memcpy(url_buf, url, url_len);
    url_buf[url_len] = '\0';
    jstring jurl = (*env)->NewStringUTF(env, url_buf);
    free(url_buf);

    // Create body byte array
    jbyteArray jbody = (*env)->NewByteArray(env, body_len);
    (*env)->SetByteArrayRegion(env, jbody, 0, body_len, (const jbyte *)body);

    // Call Java: byte[] result = callback.execute(url, body)
    jbyteArray jresult = (jbyteArray)(*env)->CallObjectMethod(env, g_http_callback, g_http_method, jurl, jbody);

    int32_t written = -1;
    if (jresult) {
        jsize rlen = (*env)->GetArrayLength(env, jresult);
        if ((uint32_t)rlen <= out_len) {
            (*env)->GetByteArrayRegion(env, jresult, 0, rlen, (jbyte *)out);
            written = rlen;
        }
        (*env)->DeleteLocalRef(env, jresult);
    }

    (*env)->DeleteLocalRef(env, jurl);
    (*env)->DeleteLocalRef(env, jbody);

    if (attached) (*g_jvm)->DetachCurrentThread(g_jvm);
    return written;
}

JNIEXPORT void JNICALL JNI_FN(nativeSetHttpCallback)(JNIEnv *env, jobject obj, jobject callback) {
    if (g_http_callback) (*env)->DeleteGlobalRef(env, g_http_callback);
    g_http_callback = (*env)->NewGlobalRef(env, callback);

    jclass cls = (*env)->GetObjectClass(env, callback);
    g_http_method = (*env)->GetMethodID(env, cls, "execute", "(Ljava/lang/String;[B)[B");

    wimg_set_http_callback(jni_http_callback);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsConnect)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    const uint8_t *ptr = wimg_fints_connect((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsSendTan)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    const uint8_t *ptr = wimg_fints_send_tan((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsFetch)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    const uint8_t *ptr = wimg_fints_fetch((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return ptr_to_jstring(env, ptr);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsGetBanks)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_fints_get_banks());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsGetTanMedia)(JNIEnv *env, jobject obj) {
    return ptr_to_jstring(env, wimg_fints_get_tan_media());
}

JNIEXPORT jstring JNICALL JNI_FN(nativeFintsSetTanMedium)(JNIEnv *env, jobject obj, jstring json) {
    const char *data = (*env)->GetStringUTFChars(env, json, NULL);
    jsize len = (*env)->GetStringUTFLength(env, json);
    const uint8_t *ptr = wimg_fints_set_tan_medium((const uint8_t *)data, len);
    (*env)->ReleaseStringUTFChars(env, json, data);
    return ptr_to_jstring(env, ptr);
}

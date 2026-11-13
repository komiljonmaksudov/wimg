package com.wimg.app.ui.components

import java.util.concurrent.ConcurrentHashMap

/**
 * Last loaded data per screen (key includes the screen's parameters). A screen
 * starts from this, so switching places never shows an empty first frame; it
 * then reloads quietly. In memory only, gone when the process ends.
 */
object ScreenCache {
    private val values = ConcurrentHashMap<String, Any>()

    @Suppress("UNCHECKED_CAST")
    fun <T> get(key: String): T? = values[key] as T?

    fun put(key: String, value: Any) { values[key] = value }

    fun clear() = values.clear()
}

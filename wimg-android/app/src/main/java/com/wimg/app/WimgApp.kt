package com.wimg.app

import android.app.Application
import com.wimg.app.bridge.LibWimg
import com.wimg.app.bridge.WimgJni
import com.wimg.app.services.FintsHttpCallback

class WimgApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            LibWimg.initialize(this)
            // Register FinTS HTTP callback (OkHttp for bank HTTPS requests)
            com.wimg.app.bridge.LibWimg.native { WimgJni.nativeSetHttpCallback(FintsHttpCallback()) }
            com.wimg.app.services.MonthEndWorker.schedule(this)
        } catch (e: Exception) {
            initError = e.message
        }
    }

    companion object {
        var initError: String? = null
    }
}

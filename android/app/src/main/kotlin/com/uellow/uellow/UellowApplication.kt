package com.uellow.uellow

import android.util.Log
import io.flutter.app.FlutterApplication
import com.tiktok.TikTokBusinessSdk
import com.tiktok.TikTokBusinessSdk.TTConfig

/**
 * Custom Application that boots the TikTok Business SDK so installs/launches
 * and in-app events flow to TikTok Events Manager (App ID 7651731222326050834)
 * for ad tracking & optimisation. Wrapped in try/catch so an SDK hiccup can
 * never crash the app.
 */
class UellowApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        try {
            val ttConfig = TTConfig(applicationContext)
                .setAppId("com.uellow.app")
                .setTTAppId("7651731222326050834")
            TikTokBusinessSdk.initializeSdk(ttConfig)
            TikTokBusinessSdk.startTrack()
        } catch (e: Throwable) {
            Log.e("UellowApplication", "TikTok SDK init failed", e)
        }
    }
}

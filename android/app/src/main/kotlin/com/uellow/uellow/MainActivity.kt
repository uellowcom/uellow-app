package com.uellow.uellow

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.tiktok.TikTokBusinessSdk
import com.tiktok.appevents.base.EventName
import com.tiktok.appevents.contents.TTContentParams
import com.tiktok.appevents.contents.TTContentsEventConstants
import com.tiktok.appevents.contents.TTAddToCartEvent
import com.tiktok.appevents.contents.TTAddToWishlistEvent
import com.tiktok.appevents.contents.TTCheckoutEvent
import com.tiktok.appevents.contents.TTPurchaseEvent
import com.tiktok.appevents.contents.TTViewContentEvent

class MainActivity : FlutterActivity() {
    private val channelName = "uellow/tiktok"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "identify" -> {
                            TikTokBusinessSdk.identify(
                                call.argument<String>("externalId") ?: "",
                                call.argument<String>("externalUserName"),
                                call.argument<String>("phoneNumber"),
                                call.argument<String>("email")
                            )
                            result.success(true)
                        }
                        "logout" -> {
                            TikTokBusinessSdk.logout()
                            result.success(true)
                        }
                        "trackSimple" -> {
                            val name = call.argument<String>("event") ?: ""
                            TikTokBusinessSdk.trackTTEvent(EventName.valueOf(name))
                            result.success(true)
                        }
                        "trackContent" -> {
                            trackContent(call)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    Log.e("TikTokBridge", "method ${call.method} failed", e)
                    result.success(false)
                }
            }
    }

    private fun trackContent(call: MethodCall) {
        val type = call.argument<String>("type") ?: return
        val builder = when (type) {
            "AddToCart" -> TTAddToCartEvent.newBuilder()
            "ViewContent" -> TTViewContentEvent.newBuilder()
            "Checkout" -> TTCheckoutEvent.newBuilder()
            "Purchase" -> TTPurchaseEvent.newBuilder()
            "AddToWishlist" -> TTAddToWishlistEvent.newBuilder()
            else -> return
        }

        call.argument<String>("description")?.let { builder.setDescription(it) }
        call.argument<String>("contentType")?.let { builder.setContentType(it) }
        call.argument<String>("contentId")?.let { builder.setContentId(it) }
        (call.argument<Number>("value"))?.let { builder.setValue(it.toDouble()) }
        call.argument<String>("currency")?.let { code ->
            try { builder.setCurrency(TTContentsEventConstants.Currency.valueOf(code)) } catch (_: Throwable) {}
        }

        val cp = TTContentParams.newBuilder()
        call.argument<String>("contentId")?.let { cp.setContentId(it) }
        call.argument<String>("contentName")?.let { cp.setContentName(it) }
        call.argument<String>("contentCategory")?.let { cp.setContentCategory(it) }
        call.argument<String>("brand")?.let { cp.setBrand(it) }
        (call.argument<Number>("price"))?.let { cp.setPrice(it.toFloat()) }
        (call.argument<Number>("quantity"))?.let { cp.setQuantity(it.toInt()) }
        builder.setContents(cp.build())

        TikTokBusinessSdk.trackTTEvent(builder.build())
    }
}

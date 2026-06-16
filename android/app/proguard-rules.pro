# TikTok Business SDK — keep SDK classes
-keep class com.tiktok.** { *; }
-keep class com.android.billingclient.api.** { *; }
-keep class androidx.lifecycle.** { *; }

# TikTok references the Play Billing client for optional IAP auto-tracking,
# which we don't depend on. Silence R8's missing-class errors for those.
-dontwarn com.android.billingclient.api.**
-dontwarn com.tiktok.**

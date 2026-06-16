import Flutter
import UIKit
import ActivityKit
import TikTokBusinessSDK
import AppTrackingTransparency

// =============================================================================
// AppDelegate — registers the com.uellow.liveactivity MethodChannel so the
// Flutter side can start, update, and end a Live Activity that surfaces
// the live order status in the Lock Screen + Dynamic Island.
//
// The Live Activity itself is declared in a separate Widget Extension
// target (UellowLiveActivity/UellowLiveActivity.swift). The shared
// UellowOrderAttributes type lives in Runner/UellowOrderAttributes.swift
// (compiled into both targets). When the channel receives an 'update'
// call before the activity exists, it requests one; subsequent calls
// update the current one. The activity ends on the explicit 'end' call
// (or after 8 hours, per the system policy).
// =============================================================================

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var currentActivity: Any?
    // v2.2.48 — kept so the token observer can call back into Flutter.
    private var laChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // TikTok Business SDK — Events Manager (Apple App ID 6769010765,
        // TikTok App ID 7651728981667528722). LaunchApp/Install are auto-tracked.
        if let ttConfig = TikTokConfig(appId: "6769010765", tiktokAppId: "7651728981667528722") {
            TikTokBusiness.initializeSdk(ttConfig)
        }

        let controller = window?.rootViewController as? FlutterViewController
        if let controller = controller {
            let channel = FlutterMethodChannel(
                name: "com.uellow.liveactivity",
                binaryMessenger: controller.binaryMessenger)
            channel.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self else { return }
                self.handle(call: call, result: result)
            }
            self.laChannel = channel

            // TikTok event bridge — same channel/contract as Android.
            let ttChannel = FlutterMethodChannel(
                name: "uellow/tiktok",
                binaryMessenger: controller.binaryMessenger)
            ttChannel.setMethodCallHandler { [weak self] (call, result) in
                self?.handleTikTok(call: call, result: result)
            }
        }

        // App Tracking Transparency prompt (iOS 14+) — needed for IDFA attribution.
        if #available(iOS 14, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                ATTrackingManager.requestTrackingAuthorization { _ in }
            }
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        if #available(iOS 16.1, *) {
            switch call.method {
            case "update":
                guard let args = call.arguments as? [String: Any],
                      let orderId = args["orderId"] as? Int,
                      let title = args["title"] as? String,
                      let body = args["body"] as? String,
                      let progress = args["progress"] as? Int else {
                    result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
                    return
                }
                let progressFraction = max(0.0, min(1.0, Double(progress) / 100.0))
                let state = UellowOrderAttributes.ContentState(
                    title: title, body: body, progress: progressFraction)

                if let activity = currentActivity as? Activity<UellowOrderAttributes> {
                    Task { await activity.update(using: state) }
                    result(true)
                } else {
                    do {
                        let attrs = UellowOrderAttributes(orderId: orderId)
                        // v2.2.48 — pushType:.token so iOS issues a per-activity
                        // APNs token; we forward it to the backend which then
                        // pushes remote updates even when the app is closed.
                        let activity = try Activity<UellowOrderAttributes>.request(
                            attributes: attrs, contentState: state, pushType: .token)
                        currentActivity = activity
                        if #available(iOS 16.2, *) {
                            self.observeLiveActivityToken(activity, orderId: orderId)
                        }
                        result(true)
                    } catch {
                        result(FlutterError(code: "ACTIVITY_FAIL",
                                            message: error.localizedDescription, details: nil))
                    }
                }
            case "end":
                if let activity = currentActivity as? Activity<UellowOrderAttributes> {
                    Task { await activity.end(dismissalPolicy: .immediate) }
                    currentActivity = nil
                }
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED",
                                message: "Live Activities require iOS 16.1+",
                                details: nil))
        }
    }

    // v2.2.48 — راقب توكن دفع النشاط وأرسله إلى Flutter ليُسجَّل في الخادم.
    @available(iOS 16.2, *)
    private func observeLiveActivityToken(
        _ activity: Activity<UellowOrderAttributes>, orderId: Int) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    self.laChannel?.invokeMethod(
                        "liveActivityToken",
                        arguments: ["orderId": orderId, "token": token])
                }
            }
        }
    }

    // =========================================================================
    // TikTok Business SDK bridge — mirrors the Android MainActivity contract
    // (channel "uellow/tiktok"). All calls are best-effort; failures never
    // surface to Flutter as exceptions.
    // =========================================================================
    private func handleTikTok(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "identify":
            TikTokBusiness.identify(
                withExternalID: (args["externalId"] as? String) ?? "",
                externalUserName: args["externalUserName"] as? String,
                phoneNumber: args["phoneNumber"] as? String,
                email: args["email"] as? String)
            result(true)
        case "logout":
            TikTokBusiness.logout()
            result(true)
        case "trackSimple":
            let name = (args["event"] as? String) ?? ""
            TikTokBusiness.trackTTEvent(ttSimpleEvent(name))
            result(true)
        case "trackContent":
            trackTikTokContent(args)
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // TTEventName is an NS_TYPED_ENUM (struct wrapping a String); TikTokBaseEvent
    // takes a plain String, so pass the constant's .rawValue.
    private func ttSimpleEvent(_ key: String) -> TikTokBaseEvent {
        switch key {
        case "LAUNCH_APP":       return TikTokBaseEvent(eventName: TTEventName.launchAPP.rawValue)
        case "ADD_PAYMENT_INFO": return TikTokBaseEvent(eventName: TTEventName.addPaymentInfo.rawValue)
        case "REGISTRATION":     return TikTokBaseEvent(eventName: TTEventName.registration.rawValue)
        case "LOGIN":            return TikTokBaseEvent(eventName: TTEventName.login.rawValue)
        case "SEARCH":           return TikTokBaseEvent(eventName: TTEventName.search.rawValue)
        default:                 return TikTokBaseEvent(eventName: key)
        }
    }

    private func ttCurrency(_ code: String) -> TTCurrency? {
        switch code {
        case "KWD": return .KWD
        case "USD": return .USD
        case "SAR": return .SAR
        case "AED": return .AED
        case "BHD": return .BHD
        case "QAR": return .QAR
        case "OMR": return .OMR
        case "EUR": return .EUR
        case "GBP": return .GBP
        default: return nil
        }
    }

    private func trackTikTokContent(_ args: [String: Any]) {
        let type = (args["type"] as? String) ?? ""
        let event: TikTokContentsEvent
        switch type {
        case "AddToCart":      event = TikTokAddToCartEvent()
        case "ViewContent":    event = TikTokViewContentEvent()
        case "Checkout":       event = TikTokCheckoutEvent()
        case "Purchase":       event = TikTokPurchaseEvent()
        case "AddToWishlist":  event = TikTokAddToWishlistEvent()
        default: return
        }
        if let cid = args["contentId"] as? String { event.setContentId(cid) }
        if let ct = args["contentType"] as? String { event.setContentType(ct) }
        if let desc = args["description"] as? String { event.setDescription(desc) }
        if let cur = args["currency"] as? String, let ttc = ttCurrency(cur) {
            event.setCurrency(ttc)
        }
        if let val = args["value"] as? NSNumber { event.setValue(val.stringValue) }

        let content = TikTokContentParams()
        if let p = args["price"] as? NSNumber { content.price = p }
        if let q = args["quantity"] as? NSNumber { content.quantity = q.intValue }
        if let b = args["brand"] as? String { content.brand = b }
        if let n = args["contentName"] as? String { content.contentName = n }
        event.setContents([content])

        TikTokBusiness.trackTTEvent(event)
    }
}

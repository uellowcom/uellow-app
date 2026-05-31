import Flutter
import UIKit
import ActivityKit

// =============================================================================
// AppDelegate — registers the com.uellow.liveactivity MethodChannel so the
// Flutter side can start, update, and end a Live Activity that surfaces
// the live order status in the Lock Screen + Dynamic Island.
//
// The Live Activity itself is declared in a separate Widget Extension
// target (UellowOrderActivity.swift). When the channel receives an
// 'update' call before the activity exists, it requests one; subsequent
// calls update the current one. The activity ends on the explicit
// 'end' call (or after 8 hours, per the system policy).
// =============================================================================

@available(iOS 16.1, *)
struct UellowOrderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var body: String
        var progress: Double  // 0..1
    }
    var orderId: Int
}

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var currentActivity: Any?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as? FlutterViewController
        if let controller = controller {
            let channel = FlutterMethodChannel(
                name: "com.uellow.liveactivity",
                binaryMessenger: controller.binaryMessenger)
            channel.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self else { return }
                self.handle(call: call, result: result)
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
                        let activity = try Activity<UellowOrderAttributes>.request(
                            attributes: attrs, contentState: state, pushType: nil)
                        currentActivity = activity
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
}

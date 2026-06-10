// =============================================================================
// UellowOrderAttributes — SHARED Live Activity attributes.
//
// This single file is compiled into BOTH targets:
//   • Runner               (the app — starts/updates/ends the activity)
//   • UellowLiveActivity   (the widget extension — renders it)
//
// ActivityKit routes a running activity to its widget by the attributes
// TYPE NAME, so the declaration must live in one shared source file that
// both targets build. Do NOT duplicate this struct anywhere else.
//
// @available(iOS 16.1, *) is required because Runner's deployment target
// is 15.5 and ActivityAttributes only exists on 16.1+.
// =============================================================================
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct UellowOrderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var body: String
        var progress: Double  // 0..1
    }
    var orderId: Int
}

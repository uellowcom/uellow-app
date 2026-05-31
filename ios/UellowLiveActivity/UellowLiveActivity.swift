// =============================================================================
// UellowLiveActivity — the Widget Extension that renders the Live
// Activity on Lock Screen + Dynamic Island. Mirrors the structure
// defined in Runner/AppDelegate.swift (UellowOrderAttributes).
//
// To enable in Xcode:
//   1. File → New → Target → Widget Extension → "Uellow Live Activity"
//      ☑ Include Live Activity. Bundle ID: com.uellow.app.liveactivity
//   2. Set Deployment Target = 16.1.
//   3. Copy this file into that target.
//   4. Ensure the Runner target has NSSupportsLiveActivities = true
//      in Info.plist (already set).
// =============================================================================
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct UellowOrderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var body: String
        var progress: Double  // 0..1
    }
    var orderId: Int
}

@available(iOS 16.1, *)
struct UellowOrderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UellowOrderAttributes.self) { context in
            // Lock Screen / banner UI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(Color(red: 0.96, green: 0.76, blue: 0.13))
                    VStack(alignment: .leading) {
                        Text(context.state.title).font(.headline)
                        Text(context.state.body).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color(red: 0.25, green: 0.14, blue: 0.01))
                }
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.96, green: 0.76, blue: 0.13))
            }
            .padding(14)
            .background(Color(red: 0.25, green: 0.14, blue: 0.01))
            .foregroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.subheadline).fontWeight(.bold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.body).font(.caption)
                    ProgressView(value: context.state.progress).tint(.yellow)
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill").foregroundColor(.yellow)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%").font(.caption2)
            } minimal: {
                Image(systemName: "shippingbox.fill").foregroundColor(.yellow)
            }
            .keylineTint(Color.yellow)
        }
    }
}

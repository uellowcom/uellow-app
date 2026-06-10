// =============================================================================
// UellowLiveActivity — the Widget Extension that renders the Live
// Activity on Lock Screen + Dynamic Island. The shared
// UellowOrderAttributes type is defined in Runner/UellowOrderAttributes.swift
// and compiled into this target too (see project.pbxproj).
//
// This target's deployment target is iOS 16.1, so no @available guards
// are needed here — ActivityKit/WidgetKit APIs are unconditionally
// available.
// =============================================================================
import ActivityKit
import SwiftUI
import WidgetKit

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

// WidgetKit entry point for the extension.
@main
struct UellowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UellowOrderActivityWidget()
    }
}

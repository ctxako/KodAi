//
//  kodai_consumer_widgetLiveActivity.swift
//  kodai-consumer-widget
//
//  Created by Charles Thomas Xavier Austin III on 6/25/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct kodai_consumer_widgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct kodai_consumer_widgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: kodai_consumer_widgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension kodai_consumer_widgetAttributes {
    fileprivate static var preview: kodai_consumer_widgetAttributes {
        kodai_consumer_widgetAttributes(name: "World")
    }
}

extension kodai_consumer_widgetAttributes.ContentState {
    fileprivate static var smiley: kodai_consumer_widgetAttributes.ContentState {
        kodai_consumer_widgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: kodai_consumer_widgetAttributes.ContentState {
         kodai_consumer_widgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: kodai_consumer_widgetAttributes.preview) {
   kodai_consumer_widgetLiveActivity()
} contentStates: {
    kodai_consumer_widgetAttributes.ContentState.smiley
    kodai_consumer_widgetAttributes.ContentState.starEyes
}

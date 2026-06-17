//
//  AddTaskWidgetLiveActivity.swift
//  AddTaskWidget
//
//  Created by ALΞXANDΞR OLKHOVSKIY on 15.01.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AddTaskWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AddTaskWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AddTaskWidgetAttributes.self) { context in
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

extension AddTaskWidgetAttributes {
    fileprivate static var preview: AddTaskWidgetAttributes {
        AddTaskWidgetAttributes(name: "World")
    }
}

extension AddTaskWidgetAttributes.ContentState {
    fileprivate static var smiley: AddTaskWidgetAttributes.ContentState {
        AddTaskWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AddTaskWidgetAttributes.ContentState {
         AddTaskWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AddTaskWidgetAttributes.preview) {
   AddTaskWidgetLiveActivity()
} contentStates: {
    AddTaskWidgetAttributes.ContentState.smiley
    AddTaskWidgetAttributes.ContentState.starEyes
}

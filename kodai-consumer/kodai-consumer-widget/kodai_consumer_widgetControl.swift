//
//  kodai_consumer_widgetControl.swift
//  kodai-consumer-widget
//
//  Control Center / Lock Screen button that opens kodAI ready for a new
//  task — the fastest route to the agent until in-app dictation lands.
//

import AppIntents
import SwiftUI
import WidgetKit

struct kodai_consumer_widgetControl: ControlWidget {
    static let kind: String = "ctxa.kodai-consumer.kodai-consumer-widget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenKodaiIntent()) {
                Label("Ask kodAI", systemImage: "pawprint.fill")
            }
        }
        .displayName("Ask kodAI")
        .description("Opens kodAI ready for a new task.")
    }
}

//
//  kodai_consumer_widgetBundle.swift
//  kodai-consumer-widget
//
//  Created by Charles Thomas Xavier Austin III on 6/25/26.
//

import WidgetKit
import SwiftUI

@main
struct kodai_consumer_widgetBundle: WidgetBundle {
    var body: some Widget {
        KodaiToolflowWidget()
        kodai_consumer_widgetControl()
        kodai_consumer_widgetLiveActivity()
    }
}

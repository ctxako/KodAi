//
//  kodAI_chatbot_devApp.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import SwiftUI

@main
struct kodAI_chatbot_devApp: App {
    @State private var showSplash = true   // branded intro: states what the instrument is before first use

    init() {
        MemoryPressureMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ChatView()
                if showSplash {
                    SplashView(onDone: {
                        withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                    })
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

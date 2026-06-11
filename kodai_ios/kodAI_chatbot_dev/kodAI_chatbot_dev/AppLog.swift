//
//  AppLog.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation

nonisolated struct AppLog: Sendable {
    let category: String

    nonisolated init(category: String) {
        self.category = category
    }

    nonisolated func event(_ message: String, since startDate: Date? = nil) {
        let elapsed = startDate.map { String(format: "+%.3fs", Date().timeIntervalSince($0)) } ?? "+-.---s"
        print("[\(category)] \(elapsed) \(message)")
    }
}

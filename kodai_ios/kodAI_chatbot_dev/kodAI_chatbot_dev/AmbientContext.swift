//
//  AmbientContext.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/8/26.
//

import Foundation

enum TimeOfDayBucket: String, Codable, Equatable, Sendable {
    case morning
    case afternoon
    case evening
    case night
}

enum WeatherStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case cached
    case fresh
    case failed
}

struct AmbientContext: Codable, Equatable, Sendable {
    let localDateDisplay: String
    let localTimeDisplay: String
    let weekday: String
    let timeOfDayBucket: TimeOfDayBucket
    let timezoneIdentifier: String
    let weatherSummary: String?
    let temperature: Int?
    let condition: String?
    let weatherStatus: WeatherStatus
    let weatherLastUpdated: Date?

    var promptBlock: String {
        let weatherLine: String
        if let weatherSummary {
            weatherLine = weatherSummary
        } else {
            weatherLine = weatherStatus == .failed ? "unavailable" : weatherStatus.rawValue
        }

        return """
        Ambient context:
        * Local date: \(localDateDisplay)
        * Local time: \(localTimeDisplay)
        * Time of day: \(timeOfDayBucket.rawValue)
        * Timezone: \(timezoneIdentifier)
        * Weather: \(weatherLine)
        """
    }
}

struct AmbientContextResult: Sendable {
    let context: AmbientContext
    let diagnostics: [String]
}

//
//  AmbientContextProvider.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/8/26.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

actor AmbientContextProvider {
    typealias StatusHandler = @Sendable (InferencePhase) -> Void

    private let cacheKey = "AmbientContextProvider.cachedWeather"
    private let userDefaults: UserDefaults
    private let calendar: Calendar

    init(userDefaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.userDefaults = userDefaults
        self.calendar = calendar
    }

    func snapshot(
        for userPrompt: String,
        onStatus: StatusHandler = { _ in }
    ) async -> AmbientContextResult {
        onStatus(.checkingLocalTime)

        let date = Date()
        let timezone = TimeZone.autoupdatingCurrent
        var diagnostics = ["Local timezone resolved"]
        let cachedWeather = cachedWeatherForToday(now: date)
        let wantsWeather = Self.isWeatherRelated(userPrompt)
        let needsAutomaticWeather = cachedWeather == nil && !hasFetchedWeatherToday(now: date)

        var weather = cachedWeather
        if let cachedWeather {
            onStatus(.usingCachedWeather)
            diagnostics.append("Cached weather reused")
            weather = cachedWeather.with(status: .cached)
        }

        if wantsWeather || needsAutomaticWeather {
            onStatus(.checkingWeather)
            let fetchedWeather = await fetchWeather(timeoutSeconds: wantsWeather ? 1.5 : 0.75)
            if let fetchedWeather {
                cache(weather: fetchedWeather)
                weather = fetchedWeather
                diagnostics.append("Weather fetched successfully")
            } else if cachedWeather != nil {
                diagnostics.append("Weather lookup failed; continued with cached weather")
            } else {
                markWeatherFetchAttempt(now: date)
                diagnostics.append(wantsWeather ? "Weather lookup failed; continued with time/date only" : "Weather unavailable; continued with time/date only")
            }
        }

        return AmbientContextResult(
            context: AmbientContext(
                localDateDisplay: Self.formatDate(date),
                localTimeDisplay: Self.formatTime(date),
                weekday: Self.formatWeekday(date),
                timeOfDayBucket: Self.timeOfDayBucket(for: date, calendar: calendar),
                timezoneIdentifier: timezone.identifier,
                weatherSummary: weather?.summary,
                temperature: weather?.temperature,
                condition: weather?.condition,
                weatherStatus: weather?.status ?? .unavailable,
                weatherLastUpdated: weather?.lastUpdated
            ),
            diagnostics: diagnostics
        )
    }

    private func cachedWeatherForToday(now: Date) -> CachedWeather? {
        guard let data = userDefaults.data(forKey: cacheKey) else { return nil }
        guard let weather = try? JSONDecoder().decode(CachedWeather.self, from: data) else { return nil }
        guard calendar.isDate(weather.lastUpdated, inSameDayAs: now) else { return nil }
        guard weather.summary != nil else { return nil }
        return weather
    }

    private func cache(weather: CachedWeather) {
        guard let data = try? JSONEncoder().encode(weather) else { return }
        userDefaults.set(data, forKey: cacheKey)
    }

    private func hasFetchedWeatherToday(now: Date) -> Bool {
        guard let data = userDefaults.data(forKey: cacheKey) else { return false }
        guard let weather = try? JSONDecoder().decode(CachedWeather.self, from: data) else { return false }
        return calendar.isDate(weather.lastUpdated, inSameDayAs: now)
    }

    private func markWeatherFetchAttempt(now: Date) {
        cache(weather: CachedWeather(summary: nil, temperature: nil, condition: nil, status: .failed, lastUpdated: now))
    }

    private func fetchWeather(timeoutSeconds: TimeInterval) async -> CachedWeather? {
        await withTaskGroup(of: CachedWeather?.self) { group in
            group.addTask {
                await Self.fetchCurrentWeather()
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int(timeoutSeconds * 1_000)))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func isWeatherRelated(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        return [
            "weather",
            "rain",
            "temperature",
            "forecast",
            "outside conditions",
            "outside",
            "umbrella",
            "coat",
            "jacket"
        ].contains { lowercased.contains($0) }
    }

    private static func timeOfDayBucket(for date: Date, calendar: Calendar) -> TimeOfDayBucket {
        switch calendar.component(.hour, from: date) {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = dateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = dateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatWeekday(_ date: Date) -> String {
        let formatter = dateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }

    private struct CachedWeather: Codable, Equatable, Sendable {
        let summary: String?
        let temperature: Int?
        let condition: String?
        let status: WeatherStatus
        let lastUpdated: Date

        func with(status: WeatherStatus) -> CachedWeather {
            CachedWeather(summary: summary, temperature: temperature, condition: condition, status: status, lastUpdated: lastUpdated)
        }
    }
}

private extension AmbientContextProvider {
    private static func fetchCurrentWeather() async -> CachedWeather? {
        #if canImport(CoreLocation) && canImport(WeatherKit)
        guard let location = await MainActor.run(body: { () -> CLLocation? in
            let locationManager = CLLocationManager()
            let authorizationStatus = locationManager.authorizationStatus
            guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
                return nil
            }
            return locationManager.location
        }) else {
            return nil
        }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let fahrenheit = weather.currentWeather.temperature.converted(to: UnitTemperature.fahrenheit).value
            let temperature = Int(fahrenheit.rounded())
            let condition = String(describing: weather.currentWeather.condition).lowercased()
            return CachedWeather(
                summary: "\(temperature)°F, \(condition)",
                temperature: temperature,
                condition: condition,
                status: .fresh,
                lastUpdated: Date()
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

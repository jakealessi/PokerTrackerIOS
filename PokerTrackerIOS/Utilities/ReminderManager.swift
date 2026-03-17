//
//  ReminderManager.swift
//  PokerTrackerIOS
//

import Foundation
import UserNotifications

enum ReminderManager {
    private static let idPrefix = "SESSION_REMINDER_"
    private static let schedule = [7, 14, 28, 84]
    private static let stateQueue = DispatchQueue(label: "ReminderManager.state")
    private static var latestScheduleToken = UUID()

    static func scheduleIfNeeded(enabled: Bool, lastSessionDate: Date?) {
        let center = UNUserNotificationCenter.current()
        let ids = schedule.map { "\(idPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let token = refreshScheduleToken()

        guard enabled else { return }

        center.getNotificationSettings { settings in
            guard isLatestScheduleToken(token) else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                scheduleReminders(center: center, lastSessionDate: lastSessionDate, token: token)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted, isLatestScheduleToken(token) else { return }
                    scheduleReminders(center: center, lastSessionDate: lastSessionDate, token: token)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    static func cancelAll() {
        _ = refreshScheduleToken()
        let ids = schedule.map { "\(idPrefix)\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func messageForDays(_ days: Int) -> String {
        let weeks = days / 7
        switch weeks {
        case 1:  return "It's been a week since your last session. Did you play and forget to log?"
        case 2:  return "Two weeks without a session logged — been playing at all?"
        case 4:  return "It's been about a month. Jump back in and log a session!"
        default: return "It's been a while! Open the app to keep your bankroll tracking up to date."
        }
    }

    private static func scheduleReminders(center: UNUserNotificationCenter, lastSessionDate: Date?, token: UUID) {
        guard isLatestScheduleToken(token) else { return }

        let calendar = Calendar.current
        let now = Date()
        let baseDate = lastSessionDate ?? now

        for days in schedule {
            guard let reminderDay = calendar.date(byAdding: .day, value: days, to: baseDate) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Log Your Session"
            content.body = messageForDays(days)
            content.sound = .default

            var comps = calendar.dateComponents([.year, .month, .day], from: reminderDay)
            comps.hour = 18
            comps.minute = 0

            guard let scheduledDate = calendar.date(from: comps),
                  scheduledDate > now,
                  isLatestScheduleToken(token) else { continue }

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "\(idPrefix)\(days)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    private static func refreshScheduleToken() -> UUID {
        stateQueue.sync {
            latestScheduleToken = UUID()
            return latestScheduleToken
        }
    }

    private static func isLatestScheduleToken(_ token: UUID) -> Bool {
        stateQueue.sync { latestScheduleToken == token }
    }
}

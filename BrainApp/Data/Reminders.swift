import Foundation
import UserNotifications

/// Local notifications: the daily question and reminders set from a pattern.
/// They are scheduled on the device; nothing leaves it.
enum Reminders {
    private static let dailyQuestionID = "brainapp.dailyQuestion"

    /// Shows the system prompt the first time; afterwards returns what the person chose.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Every day at the goal's reminder hour. Removed when turned off, or when the goal has no question.
    static func syncDailyQuestion(goal: Goal?, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyQuestionID])
        guard enabled, let goal, let question = goal.question, await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = question
        content.body = "One tap. It's how I learn what helps."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: goal.reminderHour, minute: 0), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: dailyQuestionID, content: content, trigger: trigger))
    }

    /// One reminder at `date`. False when notifications aren't allowed.
    static func remind(_ text: String, at date: Date) async -> Bool {
        guard await requestPermission() else { return false }
        let content = UNMutableNotificationContent()
        content.title = text
        content.sound = .default
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
    }
}

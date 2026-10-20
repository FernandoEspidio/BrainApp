import DeviceActivity
import ExtensionKit
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    /// Must match the context the Screen Time probe in BrainApp asks for.
    static let totalActivity = Self("Total Activity")
}

struct DayUsage: Identifiable {
    struct Category: Identifiable {
        var id: String { name }
        let name: String
        let duration: TimeInterval
    }

    var id: Date { day }
    let day: Date
    let total: TimeInterval
    let topCategories: [Category]
}

/// SPIKE: iOS hands the real numbers to this extension only. It can draw them inside BrainApp,
/// but nothing here can reach the app's code.
struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: ([DayUsage]) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [DayUsage] {
        var days: [DayUsage] = []
        for await device in data {
            for await segment in device.activitySegments {
                var categories: [DayUsage.Category] = []
                for await activity in segment.categories {
                    categories.append(DayUsage.Category(name: activity.category.localizedDisplayName ?? "Other",
                                                        duration: activity.totalActivityDuration))
                }
                days.append(DayUsage(day: segment.dateInterval.start, total: segment.totalActivityDuration,
                                     topCategories: Array(categories.sorted { $0.duration > $1.duration }.prefix(3))))
            }
        }
        return days.sorted { $0.day > $1.day }
    }
}

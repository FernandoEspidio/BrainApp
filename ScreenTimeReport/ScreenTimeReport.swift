import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ScreenTimeReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { days in
            TotalActivityView(days: days)
        }
    }
}

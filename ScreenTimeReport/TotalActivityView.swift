import SwiftUI

/// One row per day: total screen time and the top three categories.
struct TotalActivityView: View {
    let days: [DayUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if days.isEmpty {
                Text("No Screen Time data for these days.")
                    .foregroundStyle(.secondary)
            }
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(day.day, format: .dateTime.weekday(.abbreviated).day().month())
                        Spacer()
                        Text(Self.format(day.total)).bold()
                    }
                    Text(day.topCategories.map { "\($0.name) \(Self.format($0.duration))" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

#Preview {
    TotalActivityView(days: [
        DayUsage(day: .now, total: 11_520, topCategories: [
            .init(name: "Social", duration: 4_200), .init(name: "Productivity", duration: 2_400)
        ])
    ])
}

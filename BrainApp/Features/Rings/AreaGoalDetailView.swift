import SwiftUI

/// Ring detail: big ring, goal editor, last 7 periods (achievements) and the moments that count.
struct AreaGoalDetailView: View {
    @Environment(AppModel.self) private var model
    let areaID: String
    @State private var logRequest: LogRequest?

    var body: some View {
        let repo = model.repository
        let area = repo.area(id: areaID)
        let ring = repo.ringProgress(for: area)
        let history = repo.history(for: area)
        let completed = history.filter(\.isComplete).count
        let moments = repo.ringMoments(for: area)
        let goal = Binding(
            get: { repo.goal(for: areaID) },
            set: { repo.setGoal($0, for: areaID) }
        )

        ScrollView {
            VStack(spacing: 20) {
                hero(ring: ring, area: area)

                Button {
                    logRequest = LogRequest(areaID: area.id)
                } label: {
                    Label("Log \(area.name)", systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle())

                // Achievements: last 7 days/weeks as mini rings.
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(ring.goal.period == .day ? "Last 7 days" : "Last 7 weeks")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Label("\(completed)/\(history.count)", systemImage: "trophy.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(area.ringColor)
                    }
                    HStack(spacing: 0) {
                        ForEach(history) { period in
                            VStack(spacing: 6) {
                                ZStack {
                                    ActivityRing(fraction: period.fraction, color: area.ringColor, lineWidth: 5)
                                    if period.isComplete {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(area.ringColor)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                Text(label(for: period.start, period: ring.goal.period))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .cardStyle()

                GoalEditor(goal: goal, color: area.ringColor)
                    .cardStyle()

                if !moments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Counted \(ring.goal.period.short)")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        ForEach(moments.prefix(8)) { activity in
                            ActivityRow(activity: activity, area: area)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                NavigationLink {
                    AreaDetailView(areaID: area.id)
                } label: {
                    Label("Trends", systemImage: "chart.bar.fill")
                }
                .buttonStyle(SoftButtonStyle())
            }
            .padding()
        }
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle(area.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logRequest) { request in LogActivitySheet(existing: nil, presetAreaID: request.areaID) }
    }

    private func hero(ring: RingProgress, area: LifeArea) -> some View {
        VStack(spacing: 12) {
            ZStack {
                ActivityRing(fraction: ring.fraction, color: area.ringColor, lineWidth: 24)
                VStack(spacing: 2) {
                    Image(systemName: area.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(area.ringColor)
                    Text("\(ring.percent)%")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.ink)
                    Text(ring.valueText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 230, height: 230)

            if ring.isComplete {
                Label("Goal reached", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(area.ringColor)
            } else {
                Text("\(ring.goal.format(ring.remaining)) to go \(ring.goal.period.short)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.top, 8)
        .animation(.snappy, value: ring.percent)
    }

    private func label(for date: Date, period: AreaGoal.Period) -> String {
        period == .day
            ? date.formatted(.dateTime.weekday(.narrow))
            : date.formatted(.dateTime.day())
    }
}

/// − value + with unit and period pickers. Changes save immediately and the ring re-animates.
struct GoalEditor: View {
    @Binding var goal: AreaGoal
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Goal", systemImage: "target")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            HStack {
                stepButton("minus", delta: -goal.step)
                Spacer()
                Text(goal.format(goal.target))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)
                Spacer()
                stepButton("plus", delta: goal.step)
            }

            Picker("Unit", selection: $goal.unit) {
                ForEach(AreaGoal.Unit.allCases) { unit in Text(unit.label).tag(unit) }
            }
            .pickerStyle(.segmented)

            Picker("Period", selection: $goal.period) {
                ForEach(AreaGoal.Period.allCases) { period in Text(period.label).tag(period) }
            }
            .pickerStyle(.segmented)
        }
        .sensoryFeedback(.selection, trigger: goal.target)
        .onChange(of: goal.unit) { _, unit in
            // Keep the number meaningful when switching units.
            goal.target = unit == .minutes ? 30 : 3
        }
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                goal.target = min(max(goal.target + delta, goal.range.lowerBound), goal.range.upperBound)
            }
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease goal" : "Increase goal")
    }
}

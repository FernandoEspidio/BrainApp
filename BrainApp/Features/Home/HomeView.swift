import SwiftUI

/// Today: the buddy says ONE thing (what comes with your goal, or what it's waiting for), one quiet
/// line of what you logged, and the goal's daily question when it's time. Nothing else.
struct HomeView: View {
    private static let daysBack = 60

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var source = HealthKitDataSource()
    /// Nil until Health has been read. Empty when Health isn't available.
    @State private var healthDays: [HealthDay]?
    @State private var poke = 0
    @State private var showLog = false
    @State private var showSettings = false
    @State private var reminder: PendingReminder?
    @State private var reminderNote: String?

    var body: some View {
        let repo = model.repository

        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header(repo: repo)
                        if repo.isDemo { DemoBanner() }

                        BrainAvatarView(appearance: repo.snapshot.companion, stage: repo.companionStage,
                                        mood: repo.companionState().mood, size: 120, poke: poke)
                            .onTapGesture { poke += 1 }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Tap to say hi")

                        if let goal = repo.snapshot.goal {
                            today(goal: goal, repo: repo)
                        } else {
                            goalQuestion(repo: repo)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLog) { LogActivitySheet(existing: nil) }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(item: $reminder) { pending in
                ReminderSheet(reminder: pending) { set in Task { await schedule(set) } }
            }
            .task(id: repo.snapshot.goal) { await readHealth() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await readHealth() } }
            }
        }
    }

    @ViewBuilder
    private func today(goal: Goal, repo: LocalRepository) -> some View {
        let days = repo.isDemo ? SampleHealthDays.watchOwner(goal: goal) : healthDays.map { repo.hintDays(health: $0, goal: goal) }
        let day = Calendar.current.startOfDay(for: .now)

        VStack(spacing: 8) {
            BuddySaysCard(state: days.map { HintEngine.state(for: goal, days: $0) }, goal: goal) { hint, action in
                reminder = PendingReminder(text: action, time: Self.suggestedTime(for: hint.result.rule.cause))
            }
            if let reminderNote {
                Text(reminderNote)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal)

        momentsLine(repo: repo)

        if let question = Self.question(for: goal, days: days, answered: repo.dailyAnswer(for: goal, on: day) != nil) {
            DailyQuestionCard(
                goal: goal, question: question, answer: repo.dailyAnswer(for: goal, on: day),
                onRemind: repo.isDemo || repo.snapshot.remindsDailyQuestion ? nil : {
                    repo.setRemindsDailyQuestion(true)
                    Task { await Reminders.syncDailyQuestion(goal: goal, enabled: true) }
                },
                onAnswer: { repo.answerDailyQuestion($0, goal: goal, day: day) }
            )
            .padding(.horizontal)
        }
    }

    /// For people who started before goals existed.
    private func goalQuestion(repo: LocalRepository) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you protecting?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Pick one. I'll ask one question a day about it and find what comes with it.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            GoalPicker(selected: nil) { repo.setGoal($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal)
    }

    /// "Today: Library · Guitar", opening today's moments.
    @ViewBuilder
    private func momentsLine(repo: LocalRepository) -> some View {
        let moments = repo.todayMoments()
        if !moments.isEmpty {
            NavigationLink {
                ActivityListView(filterIDs: Set(moments.map(\.id)), title: "Today")
            } label: {
                HStack(spacing: 6) {
                    Text("Today:").fontWeight(.semibold)
                    Text(moments.map(\.activity.title).joined(separator: " · "))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.plain)
        }
    }

    private func header(repo: LocalRepository) -> some View {
        let name = repo.snapshot.userName
        return HStack(spacing: 10) {
            // Settings live behind the avatar.
            Button {
                showSettings = true
            } label: {
                Group {
                    if let initial = name.first {
                        Text(String(initial).uppercased()).font(.headline)
                    } else {
                        Image(systemName: "person.fill").font(.subheadline)
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
            }
            .accessibilityLabel("Settings")
            Text(name.isEmpty ? "Hi there" : "Hi, \(name)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                showLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.ink, in: Circle())
            }
            .accessibilityLabel("Log something you did")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Data

    /// The question to show, if any: from the goal's hour, and never when a Watch already measures sleep.
    /// Once answered it stays, so the answer can be changed.
    private static func question(for goal: Goal, days: [HealthDay]?, answered: Bool, now: Date = .now) -> String? {
        guard let question = goal.question else { return nil }
        if goal == .sleep, let days, HintEngine.outcome(for: .sleep, days: days) == .sleep { return nil }
        return answered || Calendar.current.component(.hour, from: now) >= goal.questionFromHour ? question : nil
    }

    /// A wind-down at 22:30, anything else at 18:00; in half an hour when that's already past.
    private static func suggestedTime(for cause: HealthConnections.Metric, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let (hour, minute) = cause == .sleep ? (22, 30) : (18, 0)
        let planned = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return planned > now ? planned : now.addingTimeInterval(30 * 60)
    }

    private func schedule(_ pending: PendingReminder) async {
        var date = pending.time
        if date <= .now { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }
        let scheduled = await Reminders.remind(pending.text, at: date)
        reminderNote = scheduled
            ? "Reminder set for \(date.formatted(date: .omitted, time: .shortened))."
            : "Notifications are off for BrainApp. You can turn them on in the Settings app."
    }

    /// Health's last days. Asks for access the first time; declined data just comes back empty.
    private func readHealth() async {
        guard !model.isDemoMode, model.repository.snapshot.goal != nil else { return }
        guard HealthKitDataSource.isAvailable else {
            healthDays = []
            return
        }
        do {
            try await source.requestAuthorization()
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -Self.daysBack, to: calendar.startOfDay(for: .now)) ?? .now
            healthDays = try await source.dailySummaries(since: start)
        } catch {
            healthDays = healthDays ?? []
        }
    }
}

/// Today's moments as small chips. Tapping one shows the brain in that moment.
struct TodayStrip: View {
    let moments: [TodayMoment]
    @Binding var selected: UUID?
    var night: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moments) { moment in
                    let isSelected = selected == moment.id
                    Button {
                        withAnimation(.snappy) { selected = isSelected ? nil : moment.id }
                    } label: {
                        Label(moment.shortValue, systemImage: moment.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(night && !isSelected ? 0.85 : 1), in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Theme.pinkDeep : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(moment.activity.title), \(moment.shortValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }
}

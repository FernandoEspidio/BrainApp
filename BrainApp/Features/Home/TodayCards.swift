import SwiftUI

/// What the buddy says on Today: one hint, or what it's waiting for. At most one button,
/// and only a pattern gets one (see `Hint.action`).
struct BuddySaysCard: View {
    /// Nil while Health is being read.
    let state: HintState?
    let goal: Goal
    var onAction: (Hint, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let state {
                if case .hint(let hint, _) = state {
                    Text(hint.strength.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.pinkDeep)
                    Text(hint.sentence)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(hint.number)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                    if let action = hint.action {
                        Button {
                            onAction(hint, action)
                        } label: {
                            Label(action, systemImage: "bell")
                        }
                        .buttonStyle(InkButtonStyle())
                        .padding(.top, 4)
                    } else if hint.strength == .hunch {
                        Text("Just a hunch so far. Keep checking in to see if it holds.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    Text(state.headline(for: goal))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
            } else {
                Text("Looking at your days…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// The goal's one daily question: one tap, then a quiet line you can change.
struct DailyQuestionCard: View {
    let goal: Goal
    let question: String
    let answer: Int?
    /// Nil hides the reminder offer (already on, or demo mode).
    var onRemind: (() -> Void)?
    var onAnswer: (Int) -> Void

    @State private var changing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let answer, !changing, goal.answers.indices.contains(answer - 1) {
                HStack {
                    Text(question)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(goal.answers[answer - 1])
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.ink)
                    Button("Change") { changing = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.pinkDeep)
                }
                .font(.subheadline)
            } else {
                Text(question)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ForEach(Array(goal.answers.enumerated()), id: \.offset) { index, label in
                        Button {
                            onAnswer(index + 1)
                            changing = false
                        } label: {
                            Text(label)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(answer == index + 1 ? Theme.Tint.rose : Theme.ink.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(answer == index + 1 ? .isSelected : [])
                    }
                }
                if let onRemind {
                    Button("Remind me every day at \(Self.hourText(goal.reminderHour))", action: onRemind)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// "9 pm", in the person's own clock format.
    static func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// "What are you protecting?": one tap on a short list. Used by onboarding and by Today.
struct GoalPicker: View {
    let selected: Goal?
    var onPick: (Goal) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Goal.allCases) { goal in
                Button {
                    onPick(goal)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: goal.symbol)
                            .frame(width: 24)
                        Text(goal.label)
                            .font(.body.weight(.medium))
                        Spacer()
                        if selected == goal {
                            Image(systemName: "checkmark").font(.subheadline.weight(.bold))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(selected == goal ? Theme.Tint.rose : Theme.ink.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == goal ? .isSelected : [])
            }
        }
    }
}

/// A pattern's action, ready to become a reminder.
struct PendingReminder: Identifiable {
    let id = UUID()
    let text: String
    var time: Date
}

/// Picks when to be reminded. A time already past today means tomorrow.
struct ReminderSheet: View {
    @State var reminder: PendingReminder
    var onSet: (PendingReminder) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reminder.text).font(.headline)
                    DatePicker("Remind me at", selection: $reminder.time, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        onSet(reminder)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

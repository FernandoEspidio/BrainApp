import SwiftUI

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

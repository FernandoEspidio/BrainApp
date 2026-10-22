import SwiftUI

/// PROTOTYPE. The verdict reveal: a moment, not a report. Big type, the buddy reacting, one number,
/// one honest line, "Why?" for the comparison behind it, and "Test another guess".
struct PrototypeRevealView: View {
    let verdict: PrototypeData.Verdict
    var onTestAnother: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 72
    @State private var appeared = false
    @State private var showsWhy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                buddy

                VStack(spacing: 14) {
                    Text("Your guess: \(verdict.guess.label)".uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Theme.pinkDeep)
                    Text(verdict.headline)
                        .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let sideEffect = verdict.sideEffect {
                        Text(sideEffect)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .rise(appeared, delay: 0.25, reduceMotion: reduceMotion)

                VStack(spacing: 4) {
                    Text(verdict.number)
                        .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.pinkDeep)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verdict.numberDetail)
                        .font(.body)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .rise(appeared, delay: 0.45, reduceMotion: reduceMotion)

                VStack(spacing: 10) {
                    if let sentence = verdict.sentence {
                        Text(sentence)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        showsWhy = true
                    } label: {
                        Label("Why?", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .rise(appeared, delay: 0.65, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 36, height: 36)
                        .background(Theme.card.opacity(0.7), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button("Test another guess") {
                    onTestAnother()
                    dismiss()
                }
                .buttonStyle(InkButtonStyle())
                Button("Keep it on Today") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .background(Theme.cream.opacity(0.95))
            .rise(appeared, delay: 0.85, reduceMotion: reduceMotion)
        }
        .background {
            LinearGradient(colors: [verdict.guess.tint, Theme.cream], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: appeared) { _, shown in shown && verdict.status == .right }
        .onAppear { appeared = true }
        .sheet(isPresented: $showsWhy) { PrototypeWhySheet(verdict: verdict) }
    }

    /// The buddy pops in; for "right", a few sparkles around it.
    private var buddy: some View {
        let size: CGFloat = typeSize.isAccessibilitySize ? 120 : 190
        return BrainAvatarView(appearance: CompanionAppearance(), stage: 0, mood: verdict.mood, size: size)
            .overlay {
                if verdict.status == .right {
                    ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { index, sparkle in
                        Image(systemName: "sparkle")
                            .font(.system(size: size * sparkle.scale, weight: .bold))
                            .foregroundStyle(index.isMultiple(of: 2) ? Theme.sun : Theme.pinkDeep)
                            .offset(x: size * sparkle.x, y: size * sparkle.y)
                            .scaleEffect(appeared ? 1 : 0.2)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(duration: 0.6, bounce: 0.5).delay(0.3 + Double(index) * 0.08), value: appeared)
                    }
                    .accessibilityHidden(true)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(duration: 0.7, bounce: 0.4), value: appeared)
            .padding(.top, 8)
    }

    /// Sparkle spots around the buddy, as fractions of its size.
    private static let sparkles: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-0.52, -0.30, 0.13), (0.50, -0.40, 0.10), (0.58, 0.12, 0.08), (-0.58, 0.20, 0.07)
    ]
}

/// "Why?": the two bars behind a verdict. They show what came with good study days, never what caused them.
struct PrototypeWhySheet: View {
    let verdict: PrototypeData.Verdict
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Good study days")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    ComparisonBars(rows: verdict.bars, tint: Theme.pinkDeep)
                        .foregroundStyle(Theme.ink)
                    if let note = verdict.barsNote {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                    }
                    Text("From your last 13 days. They show what came with your good study days, not what caused them.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(20)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Why?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension View {
    /// Fades in and rises a little after `delay`. With Reduce Motion it only fades.
    func rise(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(.easeOut(duration: 0.5).delay(delay), value: shown)
    }
}

#Preview("Reveal · Sleep") {
    PrototypeRevealView(verdict: PrototypeData.verdict(for: PrototypeData.sleep)!)
        .fontDesign(.rounded)
}

#Preview("Reveal · Coffee") {
    PrototypeRevealView(verdict: PrototypeData.verdict(for: PrototypeData.coffee)!)
        .fontDesign(.rounded)
}

#Preview("Reveal · Largest text") {
    PrototypeRevealView(verdict: PrototypeData.verdict(for: PrototypeData.sleep)!)
        .fontDesign(.rounded)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Why?") {
    PrototypeWhySheet(verdict: PrototypeData.verdict(for: PrototypeData.coffee)!)
        .fontDesign(.rounded)
}

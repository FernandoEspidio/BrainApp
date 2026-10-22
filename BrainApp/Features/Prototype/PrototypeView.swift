import SwiftUI

/// PROTOTYPE root: onboarding, then Today. The bar on top drives the demo and isn't part of the design.
struct PrototypeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var onboarded = false
    @State private var name = ""
    @State private var picks: [PrototypeData.Guess] = []
    @State private var day = PrototypeData.Day.one
    /// The other Day 14: the student studied at the library every day.
    @State private var alikeDays = false

    var body: some View {
        VStack(spacing: 0) {
            demoBar
            if onboarded {
                PrototypeTodayView(day: day, name: name, guesses: picks, alikeDays: alikeDays)
                    // A new day starts from its own made-up data.
                    .id("\(day.rawValue)-\(alikeDays)")
            } else {
                PrototypeOnboardingView(name: $name, picks: $picks) { onboarded = true }
            }
        }
        .background(Theme.cream.ignoresSafeArea())
        .tint(Theme.ink)
        .fontDesign(.rounded)
        .preferredColorScheme(.light)
    }

    private var demoBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline)
            }
            .accessibilityLabel("Close prototype")

            if onboarded {
                Picker("Day", selection: $day) {
                    ForEach(PrototypeData.Day.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Spacer()
                Label("Prototype · made-up data", systemImage: "theatermasks")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.Tint.butter, in: Capsule())
                Spacer()
            }

            Menu {
                Toggle("Library every day", isOn: $alikeDays)
                if !onboarded {
                    Button("Skip to Today") {
                        if picks.isEmpty { picks = PrototypeData.demoPicks }
                        onboarded = true
                    }
                }
                Button("Start over") {
                    onboarded = false
                    name = ""
                    picks = []
                    day = .one
                    alikeDays = false
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("Demo options")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Settings → Lab row: opens the prototype full screen, like a first run.
struct PrototypeLabRow: View {
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Prototype: Test your hunch", systemImage: "lightbulb")
        }
        .fullScreenCover(isPresented: $isOpen) { PrototypeView() }
    }
}

#Preview("Prototype") {
    PrototypeView()
}

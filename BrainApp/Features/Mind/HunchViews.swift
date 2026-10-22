import SwiftUI

struct HunchRoute: Identifiable, Hashable {
    let id: UUID
}

/// Today's single hunch question, answered in one tap. When a hunch has enough days,
/// the card invites you to see how it went instead.
struct HunchCheckInCard: View {
    let hunch: Hunch
    var onOpen: () -> Void

    @Environment(AppModel.self) private var model
    @State private var answered: Hunch.Answer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Hunch · \(min(hunch.answeredCount + 1, hunch.targetCheckIns)) of \(hunch.targetCheckIns)", systemImage: "lightbulb.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Deep.butter)
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.inkSoft)
                }
                .accessibilityLabel("Hunch details")
            }

            if hunch.isReadyToDecide {
                Text("“\(hunch.statement)”")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Button("See how it went", action: onOpen)
                    .buttonStyle(InkButtonStyle())
            } else if let answered {
                Label(answered == .unsure ? "Noted. Some days are like that." : "Noted for today ✓",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Deep.mint)
            } else {
                Text(hunch.question)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(Hunch.Answer.allCases, id: \.self) { answer in
                        Button {
                            withAnimation(.snappy) { answered = answer }
                            // Let the confirmation show for a moment before the card moves on.
                            Task {
                                try? await Task.sleep(for: .seconds(1.1))
                                model.repository.checkIn(answer, for: hunch.id)
                            }
                        } label: {
                            Label(answer.label, systemImage: answer.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(answer == .yes ? .white : Theme.ink)
                                .background(answer == .yes ? Theme.ink : Theme.ink.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sensoryFeedback(.success, trigger: answered)
        .id(hunch.id)
    }
}

/// Day dots: ✓ yes, ✗ no, ? not sure, empty = still to come.
struct HunchDots: View {
    let hunch: Hunch

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(hunch.targetCheckIns, hunch.checkIns.count), id: \.self) { index in
                let answer = index < hunch.checkIns.count ? hunch.checkIns[index].answer : nil
                ZStack {
                    Circle().fill(fill(answer))
                    if let answer {
                        Image(systemName: answer.symbol)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(answer == .yes ? .white : Theme.inkSoft)
                    }
                }
                .frame(width: 20, height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hunch.yesCount) yes out of \(hunch.answeredCount) answered days")
    }

    private func fill(_ answer: Hunch.Answer?) -> Color {
        switch answer {
        case .yes: return Theme.Deep.mint
        case .no: return Theme.ink.opacity(0.12)
        case .unsure: return Theme.Tint.butter
        case nil: return Theme.hairline
        }
    }
}

/// A hunch, its days, and (when ready) the decision — which is always yours.
struct HunchDetailSheet: View {
    let hunchID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let repo = model.repository
        NavigationStack {
            ScrollView {
                if let hunch = repo.hunch(id: hunchID) {
                    content(hunch, repo: repo).padding()
                } else {
                    ContentUnavailableView("Hunch removed", systemImage: "lightbulb.slash").padding(.top, 60)
                }
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Hunch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete hunch", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this hunch?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    repo.deleteHunch(hunchID)
                    dismiss()
                }
            }
        }
    }

    private func content(_ hunch: Hunch, repo: LocalRepository) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                TintedIcon(symbol: hunch.symbol, tint: Theme.Tint.butter, size: 48)
                Text(hunch.statement).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                if !hunch.areaIDs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(hunch.areaIDs.enumerated()), id: \.offset) { index, id in
                            let area = repo.area(id: id)
                            if index > 0 { Image(systemName: "arrow.left.and.right").font(.caption).foregroundStyle(Theme.inkSoft) }
                            Label(area.name, systemImage: area.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(area.tint, in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Connects \(hunch.areaIDs.map { repo.area(id: $0).name }.joined(separator: " and "))")
                }
                Text(hunch.status.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Every day: \(hunch.question)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                HunchDots(hunch: hunch)
                if hunch.status == .testing && !hunch.isReadyToDecide {
                    let today = hunch.answer(on: .now)
                    HStack(spacing: 8) {
                        ForEach(Hunch.Answer.allCases, id: \.self) { answer in
                            Button {
                                repo.checkIn(answer, for: hunch.id)
                            } label: {
                                Label(answer.label, systemImage: answer.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(today == answer ? .white : Theme.ink)
                                    .background(today == answer ? Theme.ink : Theme.ink.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(today == answer ? .isSelected : [])
                        }
                    }
                    Text(today == nil ? "Today" : "Today · you can change it")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            if hunch.isReadyToDecide { decision(hunch, repo: repo) }

            if hunch.status == .confirmed {
                Label("It's one of your traits now. You choose if friends see it in Friends → What friends see.",
                      systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }

            Text("A hunch is a personal check, not a proof: you decide what it means.")
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func decision(_ hunch: Hunch, repo: LocalRepository) -> some View {
        let summary: String = {
            switch hunch.leaning {
            case .holds: return "It held on \(hunch.yesCount) of \(hunch.answeredCount) days. Looks like you."
            case .doesNotHold: return "It held on \(hunch.yesCount) of \(hunch.answeredCount) days. Maybe not you, and that's a finding too."
            case .mixed, .none: return "It held on \(hunch.yesCount) of \(hunch.answeredCount) days. Mixed: it might depend on something else."
            }
        }()
        return VStack(alignment: .leading, spacing: 12) {
            Label("How it went", systemImage: "flag.checkered").font(.headline).foregroundStyle(Theme.ink)
            Text(summary).font(.subheadline).foregroundStyle(Theme.ink)
            Button { repo.setHunchStatus(.confirmed, for: hunch.id) } label: {
                Label("That's me: keep it as a trait", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle())
            HStack(spacing: 10) {
                Button("Not really") { repo.setHunchStatus(.notReally, for: hunch.id) }
                    .buttonStyle(SoftLargeButtonStyle())
                Button("3 more days") { repo.setHunchStatus(.testing, for: hunch.id) }
                    .buttonStyle(SoftLargeButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Write down something you believe about yourself, or pick a common one.
struct NewHunchSheet: View {
    var suggestionsFrom: [Discovery] = []

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var statement = ""
    @State private var areaIDs: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        let repo = model.repository
        let existing = Set(repo.snapshot.hunches.map(\.statement))
        let templates = (suggestionsFrom.prefix(2).map(HunchTemplate.from) + HunchTemplate.all)
            .filter { !existing.contains($0.statement) }

        NavigationStack {
            Form {
                Section {
                    TextField("Music helps me focus", text: $statement, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .focused($focused)
                } header: {
                    Text("I believe that…")
                } footer: {
                    Text("For the next 5 days you'll get one quick question. Then you decide if it's you.")
                }

                Section("What does it connect? (optional)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LifeArea.builtIns) { area in
                                let isOn = areaIDs.contains(area.id)
                                Button {
                                    toggle(area.id)
                                } label: {
                                    Label(area.name, systemImage: area.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(isOn ? area.tint : Theme.ink.opacity(0.05), in: Capsule())
                                        .overlay(Capsule().strokeBorder(isOn ? area.color : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }

                if !templates.isEmpty {
                    Section("Ideas") {
                        ForEach(templates) { template in
                            Button {
                                repo.addHunch(template.make(isDemo: repo.isDemo))
                                dismiss()
                            } label: {
                                Label(template.statement, systemImage: template.symbol).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("New hunch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let text = statement.trimmingCharacters(in: .whitespacesAndNewlines)
                        repo.addHunch(Hunch(statement: text, question: "Was it true today: “\(text)”?",
                                            areaIDs: areaIDs, isDemo: repo.isDemo))
                        dismiss()
                    }
                    .disabled(statement.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = areaIDs.firstIndex(of: id) {
            areaIDs.remove(at: index)
        } else {
            areaIDs.append(id)
            if areaIDs.count > 2 { areaIDs.removeFirst() }
        }
    }
}

import SwiftUI

/// First run: the steps down the side, the current one beside them.
struct WalkthroughView: View {
    @Bindable var walk: WalkthroughController

    var body: some View {
        HStack(spacing: 0) {
            List(SetupStep.allCases, id: \.self) { s in
                Label(s.title, systemImage: s < walk.step ? "checkmark.circle.fill" : (s == walk.step ? "circle.inset.filled" : "circle"))
                    .foregroundStyle(s == walk.step ? .primary : .secondary)
                    .fontWeight(s == walk.step ? .semibold : .regular)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            VStack(alignment: .leading, spacing: 14) {
                Text(walk.step.title).font(.title2).bold()
                pane
                if let working = walk.working {
                    HStack { ProgressView().controlSize(.small); Text(working).foregroundStyle(.secondary) }
                }
                if let message = walk.message {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 640, height: 440)
        .task { await walk.resume() }
    }

    @ViewBuilder private var pane: some View {
        switch walk.step {
        case .welcome: WelcomeStep(walk: walk)
        case .runtime: RuntimeStep(walk: walk)
        case .aboutYou: AboutYouStep(walk: walk)
        case .invitation: InvitationStep(walk: walk)
        case .tellDanny: TellDannyStep(walk: walk)
        case .saveKey: SaveKeyStep(walk: walk)
        case .waiting: WaitingStep(walk: walk)
        case .filling: FillingStep(walk: walk)
        case .done: DoneStep(walk: walk)
        }
    }
}

/// The "why" of a step, as in WELCOME2TV.md.
struct Why: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct ContinueButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    init(_ title: String = "Continue", enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.enabled = enabled; self.action = action
    }
    var body: some View {
        HStack { Spacer(); Button(title, action: action).keyboardShortcut(.defaultAction).disabled(!enabled) }
    }
}

import Foundation

/// The first-run walkthrough's steps, in order.
enum SetupStep: Int, CaseIterable, Sendable, Comparable {
    case welcome, runtime, aboutYou, invitation, tellDanny, saveKey, waiting, filling, done

    static func < (a: SetupStep, b: SetupStep) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .runtime: "Container runtime"
        case .aboutYou: "About you"
        case .invitation: "Your invitation"
        case .tellDanny: "Tell Danny"
        case .saveKey: "Save your key"
        case .waiting: "Waiting for Danny"
        case .filling: "Filling your folder"
        case .done: "Done"
        }
    }

    /// The same rule tv join applies: short, lowercase, starting with a letter.
    static func isGoodLogin(_ login: String) -> Bool {
        login.range(of: "^[a-z][a-z0-9-]{0,31}$", options: .regularExpression) != nil
    }
}

/// Where the walkthrough should be, from what tv says about this computer
/// and the few things only the app remembers. Quitting halfway and coming
/// back lands here.
func resumeStep(check: CheckState, status: Status?, keySaved: Bool,
                firstCatchUpDone: Bool, welcomeSeen: Bool) -> SetupStep {
    let joined = !(status?.login.isEmpty ?? true)
    if !joined && !welcomeSeen { return .welcome }
    switch check {
    case .noRuntime, .runtimeStopped: if !joined { return .runtime }
    case .notJoined: return .aboutYou
    case .stopped, .running: break
    }
    if !keySaved { return .saveKey }
    guard let sync = status?.sync, sync.connected, sync.shared else { return .waiting }
    if !firstCatchUpDone || sync.needFiles > 0 { return .filling }
    return .done
}

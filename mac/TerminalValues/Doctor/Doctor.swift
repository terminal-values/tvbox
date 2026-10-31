import Foundation
import Observation

/// Call the Doctor: tv doctor's check-up, with the fixes the app can make.
@MainActor @Observable
final class Doctor {
    let model: AppModel
    var report: DoctorReport?
    var running = false

    init(model: AppModel) { self.model = model }

    static func fixTitle(_ fix: DoctorFix) -> String {
        switch fix {
        case .startRuntime: "Start the Runtime"
        case .startBox: "Start the Box"
        case .catchUp: "Review & Catch Up…"
        case .update: "Update…"
        }
    }

    func run() async {
        running = true
        defer { running = false }
        report = try? await model.tv.json(DoctorReport.self, ["doctor", "--json"], timeout: .seconds(180))
    }

    /// Makes the fix, then checks again.
    func fix(_ fix: DoctorFix) async {
        switch fix {
        case .startRuntime:
            _ = try? await model.tv.run(["runtime-start"], timeout: .seconds(600))
            await model.refresh()
        case .startBox: await model.startBox()
        case .catchUp: model.reviewRequested = true
        case .update: model.updateRequested = true
        }
        await run()
    }

    /// The report as words, to copy or save: tv doctor's own text.
    func reportText() async -> String {
        (try? await model.tv.run(["doctor"], timeout: .seconds(180)))?.stdout ?? ""
    }
}

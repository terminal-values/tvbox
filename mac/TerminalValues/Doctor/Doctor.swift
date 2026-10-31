import Foundation
import Observation

/// Call the Doctor: tv doctor's check-up, with the fixes the app can make.
@MainActor @Observable
final class Doctor {
    let model: AppModel
    var report: DoctorReport?
    var running = false
    /// Why the check-up couldn't run, in words.
    var problem: String?

    init(model: AppModel) { self.model = model }

    /// tv, told which box this release pins, so the check-up compares with that.
    private var doctorTV: TV {
        guard let pin = model.pinned else { return model.tv }
        return TV(executable: model.tv.executable,
                  environment: model.tv.environment.merging(["TV_PINNED_REVISION": pin.revision]) { $1 })
    }

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
        do {
            report = try await doctorTV.json(DoctorReport.self, ["doctor", "--json"], timeout: .seconds(180))
            problem = nil
        } catch {
            report = nil
            problem = "The check-up couldn't run: \(error)"
        }
    }

    /// Makes the fix, then checks again.
    func fix(_ fix: DoctorFix) async {
        switch fix {
        case .startRuntime:
            _ = try? await model.tv.run(["runtime-start"], timeout: .seconds(600))
            await model.refresh()
        case .startBox: await model.startBox()
        case .catchUp: model.reviewRequested = true
        case .update:
            // A box behind this release moves to it; otherwise, look for a newer app.
            if model.pinned != nil, model.status?.revision != model.pinned?.revision {
                _ = await moveBoxIfNeeded(model: model, pinned: model.pinned)
            } else {
                model.updateRequested = true
            }
        }
        await run()
    }

    /// The report as words, to copy or save: tv doctor's own text.
    func reportText() async -> String {
        (try? await doctorTV.run(["doctor"], timeout: .seconds(180)))?.stdout ?? ""
    }
}

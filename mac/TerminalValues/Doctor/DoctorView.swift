import AppKit
import SwiftUI

/// The check-up's results, one row a check, with a fix button where tv
/// knows one, and the report to copy or save.
struct DoctorView: View {
    @Bindable var doctor: Doctor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The Doctor's report").font(.title3).bold()
                Spacer()
                if doctor.running { ProgressView().controlSize(.small) }
                Button("Run Again") { Task { await doctor.run() } }.disabled(doctor.running)
            }
            if let problem = doctor.problem { Text(problem).foregroundStyle(.red).textSelection(.enabled) }
            Form {
                ForEach(doctor.report?.results ?? []) { r in
                    LabeledContent {
                        if let fix = r.fix {
                            Button(Doctor.fixTitle(fix)) { Task { await doctor.fix(fix) } }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(r.message).fixedSize(horizontal: false, vertical: true)
                                Text(r.id).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { symbol(r.status) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Copy Report") { Task { await copy() } }
                Button("Save Report…") { Task { await save() } }
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .task { await doctor.run() }
    }

    private func symbol(_ s: DoctorStatus) -> some View {
        switch s {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .problem: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func copy() async {
        let text = await doctor.reportText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save() async {
        let text = await doctor.reportText()
        let panel = NSSavePanel()
        let day = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "tv-doctor-\(day).txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

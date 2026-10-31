import SwiftUI

struct FooterView: View {
    @Bindable var model: AppModel
    var openDoctor: () -> Void
    var canUpdate = false
    var checkForUpdates: () -> Void = {}

    var body: some View {
        HStack {
            Text("Box \((model.status?.revision ?? model.boxRevision).map { String($0.prefix(7)) } ?? "—")")
            Text("·")
            Button("Call the Doctor…", action: openDoctor)
                .buttonStyle(.link).foregroundStyle(.secondary)
            Spacer()
            if canUpdate {
                Button("Check for Updates…", action: checkForUpdates).buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

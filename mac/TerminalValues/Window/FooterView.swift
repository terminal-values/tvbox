import SwiftUI

struct FooterView: View {
    @Bindable var model: AppModel
    var openDoctor: () -> Void
    var canUpdate = false
    var checkForUpdates: () -> Void = {}

    /// The same "v0.1.16/ffedefr" as the menu's status line.
    static func tag(_ model: AppModel, app: AppVersion) -> String {
        app.tag(box: model.status?.revision ?? model.boxRevision)
    }

    var body: some View {
        HStack {
            Text(Self.tag(model, app: AppVersion(info: Bundle.main.infoDictionary ?? [:])))
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

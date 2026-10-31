import SwiftUI

struct FooterView: View {
    @Bindable var model: AppModel
    var openDoctor: () -> Void

    var body: some View {
        HStack {
            Text("Box \(model.boxRevision.map { String($0.prefix(7)) } ?? "—")")
            Text("·")
            Button("Call the Doctor…", action: openDoctor)
                .buttonStyle(.link).foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}

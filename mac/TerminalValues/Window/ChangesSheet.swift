import SwiftUI

/// What tv catch-up would bring in, shown in full before anything is applied.
struct ChangesSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var shown: Changes?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Code and instructions changed on tvhome").font(.headline)
            if let note { Text(note).foregroundStyle(.orange) }
            if let c = shown {
                ForEach(c.code.incoming) { commit in
                    Text("\(commit.author): \(commit.subject)")
                }
                Text(c.code.files.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                if let readers = c.secrets.readersDiff {
                    Text("Who can read TV's secrets is changing").font(.headline).foregroundStyle(.red)
                    diffView(readers)
                }
                diffView(c.code.diff ?? "")
            } else {
                ProgressView()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { Task { await apply() } }
                    .keyboardShortcut(.defaultAction).disabled(shown == nil || model.busy != nil)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .task { await load() }
    }

    private func diffView(_ text: String) -> some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }

    private func load() async {
        shown = try? await model.tv.json(Changes.self, ["changes", "--diff"], timeout: .seconds(60))
    }

    private func apply() async {
        guard let c = shown else { return }
        switch await model.applyChanges(c) {
        case .applied: dismiss()
        case .tvhomeMoved:
            note = "tvhome has more since you opened this. Here's the latest; nothing was applied."
            await load()
        case .clash(let words), .failed(let words):
            note = words
        }
    }
}

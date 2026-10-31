import SwiftUI

struct RecentSection: View {
    @Bindable var model: AppModel

    var body: some View {
        if let recent = model.changes?.recent, !recent.isEmpty {
            Section("Lately on tvhome") {
                ForEach(recent.prefix(4)) { c in
                    LabeledContent("\(c.author): \(c.subject)", value: Self.ago(c.when))
                }
            }
        }
    }

    static func ago(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

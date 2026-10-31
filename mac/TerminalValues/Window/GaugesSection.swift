import SwiftUI

/// CPU, memory and disk for the box, in the logo's three beam colours.
struct GaugesSection: View {
    @Bindable var model: AppModel
    static let cyan = Color(red: 0x00 / 255, green: 0xb4 / 255, blue: 0xdc / 255)
    static let violet = Color(red: 0x64 / 255, green: 0x47 / 255, blue: 0xff / 255)
    static let pink = Color(red: 0xdf / 255, green: 0x25 / 255, blue: 0x80 / 255)

    var body: some View {
        if model.isRunning {
            Section {
                gauge("CPU", value: (model.stats?.cpuPercent ?? 0) / 100, text: model.stats.map { String(format: "%.0f%%", $0.cpuPercent) }, tint: Self.cyan)
                gauge("Memory", value: Double(model.stats?.memoryBytes ?? 0) / 1_073_741_824,
                      text: model.stats.map { "\($0.memoryBytes / 1_048_576) MB" }, tint: Self.violet)
                gauge("Disk", value: Double(model.stats?.diskBytes ?? 0) / 10_737_418_240,
                      text: model.stats?.diskBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }, tint: Self.pink)
            }
        }
    }

    private func gauge(_ name: String, value: Double, text: String?, tint: Color) -> some View {
        LabeledContent {
            HStack {
                ProgressView(value: min(max(value, 0), 1)).tint(tint)
                Text(text ?? "…").monospacedDigit().frame(width: 64, alignment: .trailing)
            }
        } label: { Text(name) }
    }
}

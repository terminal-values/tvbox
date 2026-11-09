import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// What `tv phone --json` prints. The URL holds a single-use key, so it is
/// only ever drawn as a QR code: never shown as text, never copied.
struct PhoneLink: Decodable {
    let url: String
    let expires: Int
}

/// A QR code for `text`, scaled up without smoothing so its squares stay sharp.
func qrImage(for text: String, size: CGFloat = 264) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scale = max(1, (size / output.extent.width).rounded(.down))
    let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

/// Fetches a pairing link from tv and keeps its deadline.
@MainActor @Observable final class PhoneModel {
    let tv: TV
    private(set) var image: NSImage?
    private(set) var error: String?
    private(set) var loadedAt: Date?
    private(set) var lifetime = 0
    private(set) var loading = false

    init(tv: TV) { self.tv = tv }

    func load() async {
        loading = true
        image = nil
        error = nil
        defer { loading = false }
        do {
            let link = try await tv.json(PhoneLink.self, ["phone", "--json"])
            guard let img = qrImage(for: link.url) else {
                error = "The app couldn't draw the code."
                return
            }
            image = img
            lifetime = link.expires
            loadedAt = Date()
        } catch let e as TVError {
            error = e.description
        } catch {
            self.error = "\(error)"
        }
    }

    func secondsLeft(now: Date) -> Int {
        guard let loadedAt else { return 0 }
        return max(0, lifetime - Int(now.timeIntervalSince(loadedAt)))
    }
}

/// Pair a Phone…: the QR code, how to use it, and a countdown.
struct PhoneSheet: View {
    @State private var phone: PhoneModel
    @Environment(\.dismiss) private var dismiss

    init(tv: TV) { _phone = State(initialValue: PhoneModel(tv: tv)) }

    var body: some View {
        VStack(spacing: 14) {
            Text("Pair a Phone").font(.headline)
            if let image = phone.image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 264, height: 264)
                    .accessibilityLabel("QR code for pairing a phone")
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = phone.secondsLeft(now: ctx.date)
                    Text(left > 0 ? String(format: "Works for %d:%02d more", left / 60, left % 60)
                                  : "This code has expired.")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            } else if let error = phone.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().frame(width: 264, height: 264)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan this with your phone's camera and open the link. It works for ten minutes, for one phone.")
                Text("Pair in the browser your links open in. On an iPhone, use Safari or Firefox; Brave doesn't keep the pairing working yet.")
                Text("Don't add the page to your home screen: it wouldn't see the pairing.")
            }
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("New Code") { Task { await phone.load() } }.disabled(phone.loading)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .task { await phone.load() }
    }
}

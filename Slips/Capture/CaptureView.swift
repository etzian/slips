import PhotosUI
import SlipsCore
import SwiftUI

/// Capture: scan with the system scanner, or import images (the simulator has no camera). The PDF and
/// its draft row are saved before anything else happens.
struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @State private var showScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var phase: Phase = .idle

    enum Phase {
        case idle
        case saving
        case reading
        case saved(Slip)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.capture"))
                .fullScreenCover(isPresented: $showScanner) {
                    DocumentScanner { images in
                        showScanner = false
                        if !images.isEmpty { process(images: images) }
                    } onFail: { error in
                        showScanner = false
                        phase = .failed(String(describing: error))
                    }
                    .ignoresSafeArea()
                }
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    pickerItems = []
                    importImages(items)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            start
        case .saving:
            ProgressView {
                Text("capture.saving")
            }
            .accessibilityIdentifier("capture.saving")
        case .reading:
            ProgressView {
                Text("capture.reading")
            }
        case .saved(let slip):
            ReviewView(slipId: slip.id) { phase = .idle }
                .id(slip.id)
        case .failed(let detail):
            ErrorStateView(title: "capture.error.title", message: "capture.error.message", detail: detail) {
                phase = .idle
            }
        }
    }

    private var start: some View {
        ContentUnavailableView {
            Label("capture.title", systemImage: "doc.viewfinder")
        } description: {
            Text("capture.message")
        } actions: {
            VStack(spacing: EZ.Space.sm) {
                if DocumentScanner.isAvailable {
                    Button {
                        showScanner = true
                    } label: {
                        Label("capture.scan", systemImage: "camera")
                            .frame(minHeight: Metrics.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("capture.scan")
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label("capture.importImages", systemImage: "photo.on.rectangle")
                        .frame(minHeight: Metrics.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("capture.importImages")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                    // UI tests cannot drive the camera or the photo picker: a synthetic page instead.
                    Button("capture.sample") { process(images: [SamplePage.image()]) }
                        .accessibilityIdentifier("capture.sample")
                }
                #endif
            }
        }
    }

    private func importImages(_ items: [PhotosPickerItem]) {
        phase = .saving
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            if images.isEmpty {
                phase = .failed(String(localized: "capture.error.noImage"))
            } else {
                process(images: images)
            }
        }
    }

    /// JPEG + PDF off the main thread, then the file and the row; only then OCR, the text layer and
    /// the parser. A failure after the save never loses the slip: it stays a draft without fields.
    private func process(images: [UIImage]) {
        guard let profile = model.activeProfileId else { return }
        phase = .saving
        let store = model.capture
        Task {
            let saved: (Slip, [Data])
            do {
                saved = try await Task.detached(priority: .userInitiated) {
                    let pages = images.compactMap(PDFBuilder.jpeg(from:))
                    let pdf = try PDFBuilder.pdf(pages: pages)
                    return (try store.save(pdf: pdf, pageCount: pages.count, profile: profile), pages)
                }.value
            } catch {
                AppModel.log.error("capture failed: \(String(describing: error), privacy: .private)")
                phase = .failed(String(describing: error))
                return
            }
            phase = .reading
            let (slip, pages) = saved
            do {
                try await Task.detached(priority: .userInitiated) {
                    let lines = try OCRService.recognize(pages: pages)
                    let searchable = try PDFBuilder.pdf(pages: pages, text: OCRService.pageText(lines, pageCount: pages.count))
                    try store.replacePDF(of: slip.id, with: searchable)
                    let extraction = SlipParser.parse(lines, today: CalendarDay(Date()))
                    try store.recordExtraction(extraction, ocrText: SlipParser.text(of: lines), for: slip.id)
                }.value
            } catch {
                AppModel.log.error("reading failed: \(String(describing: error), privacy: .private)")
            }
            phase = .saved(slip)
        }
    }
}

#if DEBUG
/// A made-up slip page for UI tests: printed text only, no real data.
enum SamplePage {
    static func image() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 56, weight: .regular),
                                                        .foregroundColor: UIColor.black]
            let rows = ["MAGASIN FICTIF", "2026-10-20", "SOUS-TOTAL   10,00", "TPS           0,50", "TVQ           1,00", "TOTAL        11,50"]
            for (i, row) in rows.enumerated() {
                NSAttributedString(string: row, attributes: attrs).draw(at: CGPoint(x: 80, y: CGFloat(120 + i * 140)))
            }
        }
    }
}
#endif

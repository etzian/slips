import PDFKit
import PhotosUI
import SlipsCore
import SwiftUI

/// Capture: scan with the system scanner, or import images (the simulator has no camera). The PDF and
/// its draft row are saved before anything else happens.
struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @State private var showScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFiles = false
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
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                    importFiles(result)
                }
                .onChange(of: model.openedFiles, initial: true) { _, urls in
                    guard !urls.isEmpty else { return }
                    model.openedFiles = []
                    importFiles(.success(urls))
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
            ReviewView(slipId: slip.id, cancel: .discardCapture) { phase = .idle }
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
                Button {
                    showFiles = true
                } label: {
                    Label("capture.importFiles", systemImage: "folder")
                        .frame(minHeight: Metrics.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("capture.importFiles")
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

    /// Images and PDFs picked in Files (On My iPhone, iCloud Drive, a File Provider app). Each PDF page
    /// becomes a page image, so every slip goes through the same JPEG → PDF → OCR path as a scan.
    private func importFiles(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure(let error) = result { phase = .failed(String(describing: error)) }
            return
        }
        phase = .saving
        let reference = Self.referenceDay(for: urls)
        Task {
            let images = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                urls.flatMap { url -> [UIImage] in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped { url.stopAccessingSecurityScopedResource() }
                        // "Open in" copies land in Documents/Inbox; the slip keeps its own PDF.
                        if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
                    }
                    if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
                        return (0..<doc.pageCount).compactMap { doc.page(at: $0).map(Self.render) }
                    }
                    return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)).map { [$0] } ?? []
                }
            }.value
            if images.isEmpty {
                phase = .failed(String(localized: "capture.error.noImage"))
            } else {
                process(images: images, reference: reference)
            }
        }
    }

    /// The date in the first file's name ("Adobe Scan 20 oct. 2026.pdf"), else its modification day.
    private static func referenceDay(for urls: [URL]) -> CalendarDay? {
        guard let url = urls.first else { return nil }
        if let day = SlipParser.referenceDay(fromFileName: url.lastPathComponent) { return day }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { CalendarDay($0) }
    }

    /// A PDF page as an image at the scanner's resolution (long edge ≈ 2000 px), on white.
    nonisolated private static func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = PDFBuilder.maxLongEdge / max(bounds.width, bounds.height, 1)
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
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
    /// `reference`: the day the slip is known to be from or after (an imported file's name or date);
    /// a scan uses today. It decides between readings like 26/10/20 = 20 Oct 2026 or 26 Oct 2020.
    private func process(images: [UIImage], reference: CalendarDay? = nil) {
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
            var input: AssistantInput?
            do {
                input = try await Task.detached(priority: .userInitiated) { () throws -> AssistantInput in
                    let lines = try OCRService.recognize(pages: pages)
                    let searchable = try PDFBuilder.pdf(pages: pages, text: OCRService.pageText(lines, pageCount: pages.count))
                    try store.replacePDF(of: slip.id, with: searchable)
                    let today = CalendarDay(Date())
                    let referenceDay = reference ?? today
                    let extraction = SlipParser.parse(lines, today: today, reference: referenceDay)
                    let text = SlipParser.text(of: lines)
                    try store.recordExtraction(extraction, ocrText: text, for: slip.id)
                    return AssistantInput(ocrText: text, localeIdentifier: Locale.current.identifier,
                                          currencyHint: extraction.currency?.value, referenceDay: referenceDay)
                }.value
            } catch {
                AppModel.log.error("reading failed: \(String(describing: error), privacy: .private)")
            }
            phase = .saved(slip)
            // An endpoint the user consented to for every slip reads it too, with the masked text only.
            if let endpoint = model.router.endpoint(profile: slip.profileId, trigger: .automatic) {
                let slips = model.slips
                Task.detached(priority: .utility) {
                    if let current = try? slips.slip(slip.id) { await EndpointAssistants.run(endpoint, on: current, slips: slips) }
                }
            }
            // The slip is saved and on screen; the on-device model proofreads it in the background.
            if let input, !input.ocrText.isEmpty, let assistant = OnDeviceAI.assistant() {
                let slips = model.slips
                Task.detached(priority: .utility) {
                    do {
                        let reading = try await withTimeout(OnDeviceAI.timeout) { try await assistant.extract(input) }
                        try slips.recordAI(reading, assistant: assistant.id, for: slip.id)
                    } catch {
                        AppModel.log.notice("on-device AI skipped: \(String(describing: error), privacy: .private)")
                    }
                }
            }
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

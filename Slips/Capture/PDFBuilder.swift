import UIKit

/// One recognised line of text on a page, in normalised page coordinates (origin top-left, 0…1).
struct PageText: Sendable {
    var text: String
    var box: CGRect
}

/// Builds a slip's PDF: one page per scanned page, JPEG-compressed (plan §4: quality ≈ 0.7, long edge
/// ≈ 2000 px), with an optional invisible text layer from OCR so the file is searchable anywhere.
enum PDFBuilder {
    static let maxLongEdge: CGFloat = 2000
    static let jpegQuality: CGFloat = 0.7
    /// The page's long edge in PDF points (A4 height); the short edge follows the image's ratio.
    static let pageLongEdge: CGFloat = 842

    /// Downscales to the long-edge limit and re-encodes as JPEG.
    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height) * image.scale
        let factor = min(1, maxLongEdge / max(longEdge, 1))
        let target = CGSize(width: (size.width * image.scale * factor).rounded(),
                            height: (size.height * image.scale * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    /// The PDF of `pages` (JPEG data). `text[i]` is drawn invisibly over page `i` when given.
    static func pdf(pages: [Data], text: [[PageText]]? = nil) throws -> Data {
        let images = pages.compactMap(UIImage.init(data:))
        guard !images.isEmpty, images.count == pages.count else { throw PDFBuildError.unreadablePage }
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        return renderer.pdfData { context in
            for (index, image) in images.enumerated() {
                let bounds = pageBounds(for: image.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
                if let lines = text?[safe: index] {
                    drawInvisible(lines, in: bounds)
                }
            }
        }
    }

    static func pageBounds(for size: CGSize) -> CGRect {
        let longEdge = max(size.width, size.height, 1)
        let factor = pageLongEdge / longEdge
        return CGRect(x: 0, y: 0, width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
    }

    /// Text in a clear colour, sized to its box, so PDF viewers can select and search it.
    private static func drawInvisible(_ lines: [PageText], in bounds: CGRect) {
        for line in lines where !line.text.isEmpty {
            let rect = CGRect(x: line.box.minX * bounds.width, y: line.box.minY * bounds.height,
                              width: line.box.width * bounds.width, height: line.box.height * bounds.height)
            let font = UIFont.systemFont(ofSize: max(rect.height * 0.8, 1))
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.clear]
            NSAttributedString(string: line.text, attributes: attributes).draw(in: rect)
        }
    }
}

enum PDFBuildError: Error {
    case unreadablePage
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

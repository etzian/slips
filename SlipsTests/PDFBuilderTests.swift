import PDFKit
import Testing
import UIKit
@testable import Slips

@MainActor
@Suite struct PDFBuilderTests {
    /// A synthetic page: noise-free grey with drawn text, sized like a phone scan.
    private func page(_ size: CGSize = CGSize(width: 3024, height: 4032)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 120)]
            for row in 0..<20 {
                NSAttributedString(string: "FAKE STORE 0001  ITEM \(row)  9.99", attributes: attrs)
                    .draw(at: CGPoint(x: 100, y: CGFloat(150 + row * 180)))
            }
        }
    }

    @Test func jpegRespectsLongEdge() throws {
        let data = try #require(PDFBuilder.jpeg(from: page()))
        let image = try #require(UIImage(data: data))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= PDFBuilder.maxLongEdge)
    }

    @Test func pdfHasOnePagePerScanAndStaysSmall() throws {
        let pages = try [page(), page()].map { try #require(PDFBuilder.jpeg(from: $0)) }
        let pdf = try PDFBuilder.pdf(pages: pages)
        let doc = try #require(PDFDocument(data: pdf))
        #expect(doc.pageCount == 2)
        // Plan §4: a two-page slip is a few hundred kB.
        #expect(pdf.count < 1_000_000)
    }

    @Test func textLayerIsSearchable() throws {
        let pages = try [page()].map { try #require(PDFBuilder.jpeg(from: $0)) }
        let text = [[PageText(text: "TOTAL 12.34", box: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.03))]]
        let doc = try #require(PDFDocument(data: try PDFBuilder.pdf(pages: pages, text: text)))
        #expect(doc.string?.contains("TOTAL 12.34") == true)
    }

    @Test func unreadablePageRefused() {
        #expect(throws: PDFBuildError.self) { try PDFBuilder.pdf(pages: [Data("not an image".utf8)]) }
        #expect(throws: PDFBuildError.self) { try PDFBuilder.pdf(pages: []) }
    }
}

import SlipsCore
import Testing
import UIKit
@testable import Slips

@Suite struct OCRServiceTests {
    /// A synthetic slip rendered as an image: black text on white, no real data.
    private func syntheticSlip() -> Data {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 56, weight: .regular),
                                                        .foregroundColor: UIColor.black]
            let rows = ["MAGASIN FICTIF", "2026-10-20", "SOUS-TOTAL   10,00", "TPS           0,50", "TVQ           1,00", "TOTAL        11,50"]
            for (i, row) in rows.enumerated() {
                NSAttributedString(string: row, attributes: attrs).draw(at: CGPoint(x: 80, y: CGFloat(120 + i * 140)))
            }
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    @Test func recognisesAndParsesASyntheticSlip() throws {
        let lines = try OCRService.recognize(pages: [syntheticSlip()])
        #expect(lines.allSatisfy { $0.box.y >= 0 && $0.box.y <= 1 && $0.page == 0 })
        let extraction = SlipParser.parse(lines)
        #expect(extraction.total?.value == 1150)
        #expect(extraction.date?.value.iso == "2026-10-20")
    }
}

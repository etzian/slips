import SlipsCore
import UIKit
import Vision

/// On-device text recognition (plan §4): `.accurate`, French and English, no language correction so
/// numbers stay as printed. Boxes are kept so the parser can use line order and right-aligned amounts.
enum OCRService {
    /// Recognises every page (JPEG data, in order). Runs synchronously: call it off the main actor.
    nonisolated static func recognize(pages: [Data]) throws -> [OCRLine] {
        try pages.enumerated().flatMap { index, data in try recognize(page: data, index: index) }
    }

    nonisolated static func recognize(page data: Data, index: Int) throws -> [OCRLine] {
        guard let image = UIImage(data: data)?.cgImage else { throw PDFBuildError.unreadablePage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["fr-FR", "en-US"].filter(supported.contains)
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox // origin bottom-left
            return OCRLine(text: candidate.string,
                           box: SlipsCore.NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height),
                           page: index, confidence: Double(candidate.confidence))
        }
    }

    /// The lines of each page as the PDF builder's invisible text layer.
    static func pageText(_ lines: [OCRLine], pageCount: Int) -> [[PageText]] {
        (0..<pageCount).map { page in
            lines.filter { $0.page == page }.map {
                PageText(text: $0.text, box: CGRect(x: $0.box.x, y: $0.box.y, width: $0.box.width, height: $0.box.height))
            }
        }
    }
}

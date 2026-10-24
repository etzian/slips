import Foundation
import Testing
@testable import SlipsCore

@Suite struct AssistantPromptTests {
    @Test func messageHasOnlyTheTextAndHints() {
        let m = AssistantPrompt.message(AssistantInput(ocrText: "TOTAL 11,50", localeIdentifier: "fr_CA", currencyHint: "CAD"))
        #expect(m.contains("TOTAL 11,50"))
        #expect(m.contains("fr_CA"))
        #expect(m.contains("CAD"))
    }

    @Test func instructionsListEveryKey() {
        for key in Seed.allKeys { #expect(AssistantPrompt.instructions.contains(key)) }
    }

    @Test func schemaHasEveryFieldNullable() throws {
        let schema = AssistantPrompt.jsonSchema
        let props = try #require(schema["properties"] as? [String: Any])
        #expect(props.count == AssistantPrompt.fields.count)
        let total = try #require(props["total"] as? [String: Any])
        let options = try #require(total["anyOf"] as? [[String: String]])
        #expect(options == [["type": "number"], ["type": "null"]])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(JSONSerialization.isValidJSONObject(schema))
    }

    @Test func decodesLenientJSON() throws {
        let text = """
            ```json
            {"merchant": "Fake Store", "date": "2026-10-20", "subtotal": "10,00", "gst": 0.5, "qst": "$1.00",
             "total": 11.5, "tip": null, "currency": "cad", "subcategory_key": "personal.groceries", "hst": "n/a"}
            ```
            """
        let r = try #require(AssistantReading.decode(text))
        let e = r.extraction()
        #expect(e.merchant?.value == "Fake Store")
        #expect(e.date?.value.iso == "2026-10-20")
        #expect(e.subtotal?.value == 1000)
        #expect(e.gst?.value == 50)
        #expect(e.qst?.value == 100)
        #expect(e.total?.value == 1150)
        #expect(e.tip == nil)
        #expect(e.hst == nil)
        #expect(e.currency?.value == "CAD")
        #expect(e.subcategoryKey?.value == "personal.groceries")
        #expect(e.total?.confidence == 0.7)
    }

    @Test func rejectsGarbage() {
        #expect(AssistantReading.decode("I cannot read this slip.") == nil)
        let bad = AssistantReading.decode(#"{"date": "20/10/2026", "subcategory_key": "personal.yachts", "total": -3}"#)
        let e = bad?.extraction()
        #expect(e?.date == nil)
        #expect(e?.subcategoryKey == nil)
        #expect(e?.total == nil)
    }
}

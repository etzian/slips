import Foundation
import Testing
@testable import Slips

@MainActor
@Suite(.serialized) struct OnDeviceAITests {
    @Test func onByDefault() {
        let saved = UserDefaults.standard.object(forKey: OnDeviceAI.settingKey)
        defer { UserDefaults.standard.set(saved, forKey: OnDeviceAI.settingKey) }
        UserDefaults.standard.removeObject(forKey: OnDeviceAI.settingKey)
        #expect(OnDeviceAI.isOn)
    }

    @Test func turnedOffMeansNoAssistant() {
        let saved = UserDefaults.standard.object(forKey: OnDeviceAI.settingKey)
        defer { UserDefaults.standard.set(saved, forKey: OnDeviceAI.settingKey) }
        UserDefaults.standard.set(false, forKey: OnDeviceAI.settingKey)
        #expect(OnDeviceAI.assistant() == nil)
    }

    @Test func unavailableMeansNoAssistant() {
        // Wherever the model cannot run (older iOS, simulator without Apple Intelligence…), nothing runs.
        if OnDeviceAI.status != .available {
            #expect(OnDeviceAI.assistant() == nil)
        }
        #expect(!OnDeviceAI.status.message.isEmpty)
    }

    @Test func timeoutStopsASlowModel() async {
        await #expect(throws: CancellationError.self) {
            try await withTimeout(.milliseconds(50)) { try await Task.sleep(for: .seconds(5)); return 1 }
        }
        let fast = try? await withTimeout(.seconds(5)) { 42 }
        #expect(fast == 42)
    }
}

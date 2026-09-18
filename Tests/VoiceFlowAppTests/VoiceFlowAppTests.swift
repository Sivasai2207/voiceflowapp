import XCTest
@testable import VoiceFlowApp

final class VoiceFlowAppTests: XCTestCase {
    @MainActor
    func testSettingsStoreDefaults() {
        let store = SettingsStore.shared
        XCTAssertNotNil(store.selectedEngine)
        XCTAssertNotNil(store.fallbackEngine)
        XCTAssertNotNil(store.outputMode)
        XCTAssertNotNil(store.hotkeyMode)
        XCTAssertNotNil(store.accentColor)
    }
    
    func testTranscriptionEngines() {
        XCTAssertEqual(TranscriptionEngine.allCases.count, 2)
        XCTAssertEqual(TranscriptionEngine.apple.rawValue, "Apple Speech")
        XCTAssertEqual(TranscriptionEngine.parakeet.rawValue, "Parakeet (Local)")
        XCTAssertFalse(TranscriptionEngine.apple.icon.isEmpty)
        XCTAssertFalse(TranscriptionEngine.parakeet.icon.isEmpty)
    }
    
    func testOutputModes() {
        XCTAssertEqual(OutputMode.allCases.count, 2)
        XCTAssertEqual(OutputMode.pasteAtCursor.rawValue, "Paste at Cursor")
        XCTAssertEqual(OutputMode.clipboardOnly.rawValue, "Copy to Clipboard")
    }
    
    func testAccentColors() {
        XCTAssertTrue(AppAccentColor.allCases.count >= 5)
        for accent in AppAccentColor.allCases {
            XCTAssertFalse(accent.rawValue.isEmpty)
        }
    }
    
    @MainActor
    func testAudioDeviceManager() {
        let manager = AudioDeviceManager.shared
        XCTAssertNotNil(manager.availableInputs)
    }
}

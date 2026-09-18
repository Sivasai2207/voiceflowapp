import XCTest
@testable import VoiceFlowApp

final class SpeechPolishingTests: XCTestCase {
    
    func testFillerWordRemoval() {
        let input = "Um hello uh this is like um a test"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: false)
        XCTAssertFalse(output.contains("Um"))
        XCTAssertFalse(output.contains("uh"))
        XCTAssertTrue(output.contains("Hello"))
        XCTAssertTrue(output.contains("test"))
    }
    
    func testStutterRemoval() {
        let input = "I I went to to the the market"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: false)
        XCTAssertEqual(output, "I went to the market")
    }
    
    func testSpokenPunctuationConversion() {
        let input = "Hello comma this is great period"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: false)
        XCTAssertEqual(output, "Hello, this is great.")
    }
    
    func testQuestionMarkAutoPunctuation() {
        let input = "how are you today"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: true)
        XCTAssertEqual(output, "How are you today?")
    }
    
    func testStatementAutoPunctuation() {
        let input = "we should schedule a meeting tomorrow"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: true)
        XCTAssertEqual(output, "We should schedule a meeting tomorrow.")
    }
    
    func testContractionRestoration() {
        let input = "i dont think we cant do it"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: false)
        XCTAssertTrue(output.contains("don't"))
        XCTAssertTrue(output.contains("can't"))
        XCTAssertTrue(output.hasPrefix("I"))
    }
    
    func testWisprFlowFullSentence() {
        let input = "um i was thinking we we should visit them on monday period"
        let output = SpeechPolishingService.shared.polish(transcript: input, autoPunctuation: true)
        XCTAssertEqual(output, "I was thinking we should visit them on monday.")
    }

    func testReferenceLibraryPreservesExactTermsWithoutPartialReplacement() {
        let entries = [
            DictionaryEntry(word: "VoiceFlow"),
            DictionaryEntry(word: "data")
        ]

        let output = SpeechPolishingService.shared.polish(
            transcript: "voiceflow will review the database and data",
            autoPunctuation: false,
            dictionaryEntries: entries
        )

        XCTAssertEqual(output, "VoiceFlow will review the database and data")
    }
}

import XCTest
@testable import Sprech

final class TextProcessingServiceTests: XCTestCase {
    func testProcessRemovesGermanFillers() async {
        let config = TextProcessingConfig(
            removeFillerWords: true,
            normalizeWhitespace: true,
            correctPunctuation: false,
            languages: [.german],
            aggressiveness: 0.5
        )

        let result = await TextProcessingService.process("äh das ist ähm ein test", with: config)

        XCTAssertEqual(result.processed, "das ist ein test")
        XCTAssertEqual(result.statistics.fillerWordsRemoved, 2)
    }

    func testProcessReturnsInputWhenNoProcessingEnabled() async {
        let config = TextProcessingConfig(
            removeFillerWords: false,
            normalizeWhitespace: false,
            correctPunctuation: false,
            languages: [.german, .english],
            aggressiveness: 0.5
        )

        let result = await TextProcessingService.process("  no changes please  ", with: config)

        XCTAssertEqual(result.processed, "no changes please")
        XCTAssertEqual(result.statistics.fillerWordsRemoved, 0)
        XCTAssertEqual(result.statistics.whitespaceNormalizations, 0)
        XCTAssertEqual(result.statistics.punctuationCorrections, 0)
    }
}

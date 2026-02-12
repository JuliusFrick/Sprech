// TextProcessingService.swift
// Sprech - Mac Dictation App
// Hauptservice für Textverarbeitung

import Foundation

/// Main service for processing transcribed text
/// Coordinates filler word removal, punctuation correction, and whitespace normalization
public actor TextProcessingService {
    
    // MARK: - Properties
    
    private let config: TextProcessingConfig
    private let fillerRemover: FillerWordRemover
    
    // MARK: - Initialization
    
    public init(config: TextProcessingConfig = .bilingual) {
        self.config = config
        self.fillerRemover = FillerWordRemover(config: config)
    }
    
    // MARK: - Public API
    
    /// Process text with all configured transformations
    /// - Parameter text: Raw transcribed text
    /// - Returns: ProcessedText with cleaned text and statistics
    public func process(_ text: String) async -> ProcessedText {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard !text.isEmpty else {
            return ProcessedText(
                original: text,
                processed: text,
                statistics: .empty
            )
        }
        
        var result = text
        var fillerWordCounts: [String: Int] = [:]
        var whitespaceNormalizations = 0
        var punctuationCorrections = 0
        
        // Step 1: Remove filler words
        if config.removeFillerWords {
            let (cleaned, counts) = await fillerRemover.removeFillers(from: result)
            result = cleaned
            fillerWordCounts = counts
        }
        
        // Step 2: Correct punctuation
        if config.correctPunctuation {
            let (corrected, corrections) = correctPunctuation(in: result)
            result = corrected
            punctuationCorrections = corrections
        }
        
        // Step 3: Normalize whitespace
        if config.normalizeWhitespace {
            let (normalized, normalizations) = normalizeWhitespace(in: result)
            result = normalized
            whitespaceNormalizations = normalizations
        }
        
        // Step 4: Final cleanup
        result = finalCleanup(result)
        
        let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let statistics = ProcessingStatistics(
            fillerWordsRemoved: fillerWordCounts.values.reduce(0, +),
            fillerWordCounts: fillerWordCounts,
            whitespaceNormalizations: whitespaceNormalizations,
            punctuationCorrections: punctuationCorrections,
            processingTimeMs: processingTime
        )
        
        return ProcessedText(
            original: text,
            processed: result,
            statistics: statistics
        )
    }
    
    /// Process text with a specific configuration (one-off)
    /// - Parameters:
    ///   - text: Raw transcribed text
    ///   - config: Configuration to use for this processing
    /// - Returns: ProcessedText with cleaned text and statistics
    public static func process(_ text: String, with config: TextProcessingConfig) async -> ProcessedText {
        let service = TextProcessingService(config: config)
        return await service.process(text)
    }
    
    // MARK: - Punctuation Correction
    
    private func correctPunctuation(in text: String) -> (String, Int) {
        var result = text
        var corrections = 0
        
        // Fix double punctuation (e.g., ".." -> ".")
        let doublePunctPattern = try? NSRegularExpression(pattern: "([.!?]){2,}", options: [])
        if let regex = doublePunctPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            corrections += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1"
            )
        }
        
        // Fix space before punctuation (e.g., "word ." -> "word.")
        let spaceBeforePunctPattern = try? NSRegularExpression(pattern: "\\s+([.!?,;:])", options: [])
        if let regex = spaceBeforePunctPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            corrections += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1"
            )
        }
        
        // Ensure space after punctuation (e.g., "word.Next" -> "word. Next")
        let noSpaceAfterPunctPattern = try? NSRegularExpression(
            pattern: "([.!?])([A-ZÄÖÜ])",
            options: []
        )
        if let regex = noSpaceAfterPunctPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            corrections += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1 $2"
            )
        }
        
        // Fix comma spacing (e.g., "word,word" -> "word, word")
        let commaSpacingPattern = try? NSRegularExpression(
            pattern: ",([^\\s\\d])",
            options: []
        )
        if let regex = commaSpacingPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            corrections += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ", $1"
            )
        }
        
        // Capitalize first letter after sentence-ending punctuation
        result = capitalizeSentenceStarts(result, corrections: &corrections)
        
        return (result, corrections)
    }
    
    private func capitalizeSentenceStarts(_ text: String, corrections: inout Int) -> String {
        var result = ""
        var capitalizeNext = true
        
        for char in text {
            if capitalizeNext && char.isLetter {
                let uppercased = char.uppercased()
                if String(char) != uppercased {
                    corrections += 1
                }
                result.append(contentsOf: uppercased)
                capitalizeNext = false
            } else {
                result.append(char)
                if ".!?".contains(char) {
                    capitalizeNext = true
                } else if !char.isWhitespace {
                    capitalizeNext = false
                }
            }
        }
        
        return result
    }
    
    // MARK: - Whitespace Normalization
    
    private func normalizeWhitespace(in text: String) -> (String, Int) {
        var result = text
        var normalizations = 0
        
        // Replace multiple spaces with single space
        let multipleSpacesPattern = try? NSRegularExpression(pattern: " {2,}", options: [])
        if let regex = multipleSpacesPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            normalizations += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: " "
            )
        }
        
        // Replace multiple newlines with double newline (paragraph break)
        let multipleNewlinesPattern = try? NSRegularExpression(pattern: "\\n{3,}", options: [])
        if let regex = multipleNewlinesPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            normalizations += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "\n\n"
            )
        }
        
        // Remove trailing spaces on lines
        let trailingSpacesPattern = try? NSRegularExpression(pattern: " +$", options: [.anchorsMatchLines])
        if let regex = trailingSpacesPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            normalizations += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        
        // Remove leading spaces on lines (except for intentional indentation)
        let leadingSpacesPattern = try? NSRegularExpression(pattern: "^[ ]{1,3}(?=[^\\s])", options: [.anchorsMatchLines])
        if let regex = leadingSpacesPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.numberOfMatches(in: result, options: [], range: range)
            normalizations += matches
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        
        return (result, normalizations)
    }
    
    // MARK: - Final Cleanup
    
    private func finalCleanup(_ text: String) -> String {
        var result = text
        
        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure text ends with proper punctuation if it doesn't
        if !result.isEmpty {
            let lastChar = result.last!
            if lastChar.isLetter || lastChar.isNumber {
                // Don't add punctuation - let the user decide
                // This is just cleanup, not content modification
            }
        }
        
        return result
    }
}

// MARK: - Convenience Extensions

extension TextProcessingService {
    /// Quick process with default bilingual settings
    public static func quickProcess(_ text: String) async -> String {
        let service = TextProcessingService()
        let result = await service.process(text)
        return result.processed
    }
    
    /// Check if text contains any filler words
    public func containsFillers(_ text: String) async -> Bool {
        let result = await process(text)
        return result.statistics.fillerWordsRemoved > 0
    }
}

// MARK: - Preview/Debug Support

#if DEBUG
extension TextProcessingService {
    /// Debug helper to see what would be removed
    public func debugProcess(_ text: String) async -> String {
        let result = await process(text)
        var output = """
        === Text Processing Debug ===
        Original: \(result.original)
        Processed: \(result.processed)
        
        Statistics:
        - Filler words removed: \(result.statistics.fillerWordsRemoved)
        - Whitespace normalizations: \(result.statistics.whitespaceNormalizations)
        - Punctuation corrections: \(result.statistics.punctuationCorrections)
        - Processing time: \(String(format: "%.2f", result.statistics.processingTimeMs))ms
        
        """
        
        if !result.statistics.fillerWordCounts.isEmpty {
            output += "Filler word breakdown:\n"
            for (word, count) in result.statistics.fillerWordCounts.sorted(by: { $0.value > $1.value }) {
                output += "  - \"\(word)\": \(count)x\n"
            }
        }
        
        return output
    }
}
#endif

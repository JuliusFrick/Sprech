// ProcessedText.swift
// Sprech - Mac Dictation App
// Model für verarbeiteten Text mit Metadaten

import Foundation

/// Represents text that has been processed by the TextProcessingService
public struct ProcessedText: Sendable, Equatable {
    /// The original, unmodified input text
    public let original: String
    
    /// The processed/cleaned text
    public let processed: String
    
    /// Statistics about the processing
    public let statistics: ProcessingStatistics
    
    /// Timestamp when processing occurred
    public let timestamp: Date
    
    public init(
        original: String,
        processed: String,
        statistics: ProcessingStatistics,
        timestamp: Date = .now
    ) {
        self.original = original
        self.processed = processed
        self.statistics = statistics
        self.timestamp = timestamp
    }
    
    /// Convenience check if any changes were made
    public var wasModified: Bool {
        original != processed
    }
    
    /// Percentage of text that was removed (0.0 - 1.0)
    public var reductionRatio: Double {
        guard !original.isEmpty else { return 0 }
        let originalLength = Double(original.count)
        let processedLength = Double(processed.count)
        return max(0, (originalLength - processedLength) / originalLength)
    }
}

/// Statistics about text processing operations
public struct ProcessingStatistics: Sendable, Equatable {
    /// Number of filler words removed
    public let fillerWordsRemoved: Int
    
    /// List of which filler words were found and how often
    public let fillerWordCounts: [String: Int]
    
    /// Number of whitespace normalizations performed
    public let whitespaceNormalizations: Int
    
    /// Number of punctuation corrections made
    public let punctuationCorrections: Int
    
    /// Processing duration in milliseconds
    public let processingTimeMs: Double
    
    public init(
        fillerWordsRemoved: Int = 0,
        fillerWordCounts: [String: Int] = [:],
        whitespaceNormalizations: Int = 0,
        punctuationCorrections: Int = 0,
        processingTimeMs: Double = 0
    ) {
        self.fillerWordsRemoved = fillerWordsRemoved
        self.fillerWordCounts = fillerWordCounts
        self.whitespaceNormalizations = whitespaceNormalizations
        self.punctuationCorrections = punctuationCorrections
        self.processingTimeMs = processingTimeMs
    }
    
    /// Empty statistics for when no processing is needed
    public static let empty = ProcessingStatistics()
}

/// Configuration for text processing behavior
public struct TextProcessingConfig: Sendable {
    /// Whether to remove filler words
    public var removeFillerWords: Bool
    
    /// Whether to normalize whitespace
    public var normalizeWhitespace: Bool
    
    /// Whether to correct punctuation
    public var correctPunctuation: Bool
    
    /// Languages to consider for filler word removal
    public var languages: Set<FillerLanguage>
    
    /// Aggressiveness of filler removal (0.0 = conservative, 1.0 = aggressive)
    public var aggressiveness: Double
    
    public init(
        removeFillerWords: Bool = true,
        normalizeWhitespace: Bool = true,
        correctPunctuation: Bool = true,
        languages: Set<FillerLanguage> = [.german, .english],
        aggressiveness: Double = 0.5
    ) {
        self.removeFillerWords = removeFillerWords
        self.normalizeWhitespace = normalizeWhitespace
        self.correctPunctuation = correctPunctuation
        self.languages = languages
        self.aggressiveness = min(1.0, max(0.0, aggressiveness))
    }
    
    /// Default configuration for German dictation
    public static let germanDefault = TextProcessingConfig(
        languages: [.german]
    )
    
    /// Default configuration for English dictation
    public static let englishDefault = TextProcessingConfig(
        languages: [.english]
    )
    
    /// Bilingual German/English configuration
    public static let bilingual = TextProcessingConfig(
        languages: [.german, .english]
    )
}

/// Supported languages for filler word detection
public enum FillerLanguage: String, Sendable, CaseIterable {
    case german = "de"
    case english = "en"
}

// FillerWordRemover.swift
// Sprech - Mac Dictation App
// Intelligente Entfernung von Füllwörtern

import Foundation

/// Service for detecting and removing filler words from transcribed text
public actor FillerWordRemover {
    
    // MARK: - Filler Word Definitions
    
    /// German filler words with context rules
    private static let germanFillers: [FillerWord] = [
        // Hesitation sounds - always remove
        FillerWord("äh", removalRule: .always),
        FillerWord("ähm", removalRule: .always),
        FillerWord("öhm", removalRule: .always),
        FillerWord("hm", removalRule: .always),
        FillerWord("hmm", removalRule: .always),
        
        // Common fillers - remove unless meaningful
        FillerWord("halt", removalRule: .unlessMeaningful),
        FillerWord("quasi", removalRule: .unlessMeaningful),
        FillerWord("sozusagen", removalRule: .unlessMeaningful),
        FillerWord("irgendwie", removalRule: .unlessMeaningful),
        FillerWord("gewissermaßen", removalRule: .unlessMeaningful),
        FillerWord("praktisch", removalRule: .unlessMeaningful),
        
        // Context-sensitive fillers
        FillerWord("also", removalRule: .notAtSentenceStart),
        FillerWord("ja", removalRule: .midSentenceOnly),
        FillerWord("ne", removalRule: .sentenceEndOnly),
        FillerWord("oder so", removalRule: .sentenceEndOnly),
        FillerWord("und so", removalRule: .sentenceEndOnly),
        FillerWord("oder sowas", removalRule: .sentenceEndOnly),
        FillerWord("weißt du", removalRule: .always),
        FillerWord("weisst du", removalRule: .always),
        FillerWord("verstehst du", removalRule: .always),
    ]
    
    /// English filler words with context rules
    private static let englishFillers: [FillerWord] = [
        // Hesitation sounds - always remove
        FillerWord("um", removalRule: .always),
        FillerWord("uh", removalRule: .always),
        FillerWord("er", removalRule: .always),
        FillerWord("ah", removalRule: .always),
        
        // Common fillers
        FillerWord("like", removalRule: .midSentenceOnly),
        FillerWord("you know", removalRule: .always),
        FillerWord("y'know", removalRule: .always),
        FillerWord("basically", removalRule: .unlessMeaningful),
        FillerWord("actually", removalRule: .unlessMeaningful),
        FillerWord("literally", removalRule: .unlessMeaningful),
        FillerWord("honestly", removalRule: .unlessMeaningful),
        FillerWord("I mean", removalRule: .notAtSentenceStart),
        FillerWord("kind of", removalRule: .unlessMeaningful),
        FillerWord("sort of", removalRule: .unlessMeaningful),
        FillerWord("kinda", removalRule: .unlessMeaningful),
        FillerWord("sorta", removalRule: .unlessMeaningful),
        FillerWord("right", removalRule: .sentenceEndOnly),
        FillerWord("or something", removalRule: .sentenceEndOnly),
        FillerWord("or whatever", removalRule: .sentenceEndOnly),
    ]
    
    // MARK: - Properties
    
    private let config: TextProcessingConfig
    private var fillerWords: [FillerWord] = []
    
    // MARK: - Initialization
    
    public init(config: TextProcessingConfig = .bilingual) {
        self.config = config
        self.fillerWords = Self.buildFillerList(for: config.languages)
    }
    
    private static func buildFillerList(for languages: Set<FillerLanguage>) -> [FillerWord] {
        var fillers: [FillerWord] = []
        
        if languages.contains(.german) {
            fillers.append(contentsOf: germanFillers)
        }
        if languages.contains(.english) {
            fillers.append(contentsOf: englishFillers)
        }
        
        // Sort by length descending to match longer phrases first
        return fillers.sorted { $0.word.count > $1.word.count }
    }
    
    // MARK: - Public API
    
    /// Remove filler words from text
    /// - Parameter text: Input text to process
    /// - Returns: Tuple of cleaned text and statistics
    public func removeFillers(from text: String) -> (String, [String: Int]) {
        guard !text.isEmpty else {
            return (text, [:])
        }
        
        var result = text
        var removedCounts: [String: Int] = [:]
        
        for filler in fillerWords {
            let (newText, count) = removeFiller(filler, from: result)
            if count > 0 {
                result = newText
                removedCounts[filler.word, default: 0] += count
            }
        }
        
        return (result, removedCounts)
    }
    
    // MARK: - Private Methods
    
    private func removeFiller(_ filler: FillerWord, from text: String) -> (String, Int) {
        var result = text
        var removeCount = 0
        
        // Build regex pattern for the filler word
        let pattern = buildPattern(for: filler)
        
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return (text, 0)
        }
        
        // Find all matches
        let range = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, options: [], range: range)
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            
            // Check if removal is appropriate based on context
            if shouldRemove(filler: filler, at: matchRange, in: result) {
                result.removeSubrange(matchRange)
                removeCount += 1
            }
        }
        
        return (result, removeCount)
    }
    
    private func buildPattern(for filler: FillerWord) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: filler.word)
        
        // Word boundary patterns that work with various punctuation
        // Handles: "word,", "word.", " word ", etc.
        return "(?<![\\p{L}])" + escaped + "(?![\\p{L}])"
    }
    
    private func shouldRemove(filler: FillerWord, at range: Range<String.Index>, in text: String) -> Bool {
        switch filler.removalRule {
        case .always:
            return true
            
        case .notAtSentenceStart:
            return !isAtSentenceStart(range: range, in: text)
            
        case .midSentenceOnly:
            return !isAtSentenceStart(range: range, in: text) && 
                   !isAtSentenceEnd(range: range, in: text)
            
        case .sentenceEndOnly:
            return isAtSentenceEnd(range: range, in: text)
            
        case .unlessMeaningful:
            return !seemsMeaningful(at: range, in: text)
        }
    }
    
    private func isAtSentenceStart(range: Range<String.Index>, in text: String) -> Bool {
        let beforeStart = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        
        // Start of text
        if beforeStart.isEmpty {
            return true
        }
        
        // After sentence-ending punctuation
        if let lastChar = beforeStart.last {
            return ".!?".contains(lastChar)
        }
        
        return false
    }
    
    private func isAtSentenceEnd(range: Range<String.Index>, in text: String) -> Bool {
        let afterEnd = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        
        // End of text
        if afterEnd.isEmpty {
            return true
        }
        
        // Before sentence-ending punctuation
        if let firstChar = afterEnd.first {
            return ".!?".contains(firstChar)
        }
        
        return false
    }
    
    private func seemsMeaningful(at range: Range<String.Index>, in text: String) -> Bool {
        // Conservative heuristic: if the word is emphasized or quoted, keep it
        let beforeStart = text[..<range.lowerBound]
        let afterEnd = text[range.upperBound...]
        
        // Check for quotes
        if beforeStart.last == "\"" || afterEnd.first == "\"" {
            return true
        }
        
        // Check for emphasis markers
        if beforeStart.hasSuffix("*") || afterEnd.hasPrefix("*") {
            return true
        }
        
        // Check if it appears to be defining something
        // e.g., "ist quasi ein..." vs "das ist, quasi, kompliziert"
        let afterTrimmed = afterEnd.trimmingCharacters(in: .whitespaces)
        if afterTrimmed.hasPrefix("ein") || afterTrimmed.hasPrefix("eine") ||
           afterTrimmed.hasPrefix("a ") || afterTrimmed.hasPrefix("an ") {
            // Likely meaningful comparative use
            return config.aggressiveness < 0.7
        }
        
        return false
    }
}

// MARK: - Supporting Types

/// Represents a filler word with its removal rules
private struct FillerWord {
    let word: String
    let removalRule: RemovalRule
    
    init(_ word: String, removalRule: RemovalRule) {
        self.word = word
        self.removalRule = removalRule
    }
}

/// Rules for when to remove a filler word
private enum RemovalRule {
    /// Always remove this filler
    case always
    
    /// Remove unless at sentence start (e.g., "Also, ich denke...")
    case notAtSentenceStart
    
    /// Only remove in middle of sentences
    case midSentenceOnly
    
    /// Only remove at sentence end (e.g., "...oder so.")
    case sentenceEndOnly
    
    /// Remove unless it seems to carry meaning in context
    case unlessMeaningful
}

//
//  TranslationResult.swift
//  Sprech
//
//  Model für Übersetzungsergebnisse
//

import Foundation

/// Ergebnis einer Übersetzung
public struct TranslationResult: Sendable, Codable, Identifiable {
    public let id: UUID
    
    /// Ursprünglicher Text
    public let sourceText: String
    
    /// Übersetzter Text
    public let translatedText: String
    
    /// Erkannte oder angegebene Quellsprache
    public let sourceLanguage: Language
    
    /// Zielsprache
    public let targetLanguage: Language
    
    /// Zeitstempel der Übersetzung
    public let timestamp: Date
    
    /// War die Quellsprache automatisch erkannt?
    public let wasAutoDetected: Bool
    
    /// Wurde das Ergebnis aus dem Cache geladen?
    public let fromCache: Bool
    
    public init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        timestamp: Date = Date(),
        wasAutoDetected: Bool = false,
        fromCache: Bool = false
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.timestamp = timestamp
        self.wasAutoDetected = wasAutoDetected
        self.fromCache = fromCache
    }
}

// MARK: - Equatable & Hashable

extension TranslationResult: Equatable, Hashable {
    public static func == (lhs: TranslationResult, rhs: TranslationResult) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension TranslationResult: CustomStringConvertible {
    public var description: String {
        """
        Translation: \(sourceLanguage.flag) → \(targetLanguage.flag)
        Source: "\(sourceText)"
        Result: "\(translatedText)"
        """
    }
}

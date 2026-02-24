//
//  TranslationService.swift
//  Sprech
//
//  Apple Translation Framework Integration
//

import Foundation
import Translation
import OSLog
import NaturalLanguage

public struct LanguagePair: Hashable, Sendable {
    public let source: Locale.Language?
    public let target: Locale.Language
    
    public init(source: Locale.Language?, target: Locale.Language) {
        self.source = source
        self.target = target
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(source?.minimalIdentifier)
        hasher.combine(target.minimalIdentifier)
    }
    
    public static func == (lhs: LanguagePair, rhs: LanguagePair) -> Bool {
        lhs.source?.minimalIdentifier == rhs.source?.minimalIdentifier &&
        lhs.target.minimalIdentifier == rhs.target.minimalIdentifier
    }
}

/// Service für On-Device Übersetzungen mit Apple Translation Framework
@MainActor
public final class TranslationService: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TranslationService()
    
    // MARK: - Published Properties
    
    /// Zeigt an, ob gerade eine Übersetzung läuft
    @Published public private(set) var isTranslating = false
    
    /// Letzte Übersetzung
    @Published public private(set) var lastResult: TranslationResult?
    
    /// Verfügbare Sprachpaare
    @Published public private(set) var availableLanguagePairs: Set<LanguagePair> = []
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "TranslationService")
    
    /// Cache für häufige Übersetzungen (Key: sourceText + targetLanguage)
    private var translationCache: [String: TranslationResult] = [:]
    private let maxCacheSize = 100
    
    /// Translation Session für wiederholte Übersetzungen
    private var translationSession: TranslationSession?
    private var currentLanguagePair: LanguagePair?
    
    // MARK: - Initialization
    
    private init() {
        logger.info("TranslationService initialized")
    }
    
    // MARK: - Public API
    
    /// Übersetzt Text in die Zielsprache
    /// - Parameters:
    ///   - text: Zu übersetzender Text
    ///   - targetLanguage: Zielsprache
    ///   - sourceLanguage: Quellsprache (optional, wird automatisch erkannt wenn nil)
    /// - Returns: TranslationResult mit dem übersetzten Text
    public func translate(
        _ text: String,
        to targetLanguage: Language,
        from sourceLanguage: Language? = nil
    ) async throws -> TranslationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyText
        }
        
        // Cache prüfen
        let cacheKey = makeCacheKey(text: text, target: targetLanguage, source: sourceLanguage)
        if let cached = translationCache[cacheKey] {
            logger.debug("Cache hit for translation")
            return TranslationResult(
                sourceText: cached.sourceText,
                translatedText: cached.translatedText,
                sourceLanguage: cached.sourceLanguage,
                targetLanguage: cached.targetLanguage,
                wasAutoDetected: cached.wasAutoDetected,
                fromCache: true
            )
        }
        
        isTranslating = true
        defer { isTranslating = false }
        
        let targetLocale = targetLanguage.locale
        let sourceLocale = sourceLanguage?.locale
        
        do {
            let response: TranslationSession.Response
            let detectedSource: Language
            let wasAutoDetected: Bool
            
            if let sourceLocale = sourceLocale {
                // Bekannte Quellsprache
                let pair = LanguagePair(source: sourceLocale, target: targetLocale)
                let session = try await getOrCreateSession(for: pair)
                response = try await session.translate(text)
                detectedSource = sourceLanguage!
                wasAutoDetected = false
            } else {
                // Automatische Spracherkennung
                let detectedLocale = detectSourceLocale(for: text) ?? Locale.Language(identifier: "en")
                let pair = LanguagePair(source: detectedLocale, target: targetLocale)
                let session = try await getOrCreateSession(for: pair)
                response = try await session.translate(text)
                
                // Versuche erkannte Sprache zu ermitteln
                if let lang = Language.from(locale: response.sourceLanguage) {
                    detectedSource = lang
                } else {
                    detectedSource = .english // Fallback
                }
                wasAutoDetected = true
            }
            
            let result = TranslationResult(
                sourceText: text,
                translatedText: response.targetText,
                sourceLanguage: detectedSource,
                targetLanguage: targetLanguage,
                wasAutoDetected: wasAutoDetected,
                fromCache: false
            )
            
            // In Cache speichern
            cacheResult(result, key: cacheKey)
            
            lastResult = result
            logger.info("Translation successful: \(detectedSource.rawValue) → \(targetLanguage.rawValue)")
            
            return result
            
        } catch let error as TranslationError {
            logger.error("Translation failed: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Translation failed: \(error.localizedDescription)")
            throw TranslationError.translationFailed(error)
        }
    }
    
    /// Übersetzt mehrere Texte in die Zielsprache
    /// - Parameters:
    ///   - texts: Array von zu übersetzenden Texten
    ///   - targetLanguage: Zielsprache
    ///   - sourceLanguage: Quellsprache (optional)
    /// - Returns: Array von TranslationResults
    public func translateBatch(
        _ texts: [String],
        to targetLanguage: Language,
        from sourceLanguage: Language? = nil
    ) async throws -> [TranslationResult] {
        var results: [TranslationResult] = []
        
        for text in texts {
            let result = try await translate(text, to: targetLanguage, from: sourceLanguage)
            results.append(result)
        }
        
        return results
    }
    
    /// Prüft ob ein Sprachpaar verfügbar ist
    /// - Parameters:
    ///   - source: Quellsprache
    ///   - target: Zielsprache
    /// - Returns: true wenn das Sprachpaar unterstützt wird
    public func isLanguagePairAvailable(from source: Language, to target: Language) async -> Bool {
        let pair = LanguagePair(source: source.locale, target: target.locale)
        
        do {
            let availability = LanguageAvailability()
            let status = await availability.status(from: pair.source!, to: pair.target)
            return status == .installed || status == .supported
        }
    }
    
    /// Lädt verfügbare Sprachpaare
    public func loadAvailableLanguagePairs() async {
        var pairs: Set<LanguagePair> = []
        
        for source in Language.allCases {
            for target in Language.allCases where source != target {
                if await isLanguagePairAvailable(from: source, to: target) {
                    let pair = LanguagePair(source: source.locale, target: target.locale)
                    pairs.insert(pair)
                }
            }
        }
        
        availableLanguagePairs = pairs
        logger.info("Loaded \(pairs.count) available language pairs")
    }
    
    /// Leert den Übersetzungs-Cache
    public func clearCache() {
        translationCache.removeAll()
        logger.debug("Translation cache cleared")
    }
    
    /// Invalidiert die aktuelle Session (z.B. bei Sprachwechsel)
    public func invalidateSession() {
        translationSession = nil
        currentLanguagePair = nil
        logger.debug("Translation session invalidated")
    }
    
    // MARK: - Private Helpers
    
    private func getOrCreateSession(for pair: LanguagePair) async throws -> TranslationSession {
        // Prüfe ob aktuelle Session passt
        if let session = translationSession, currentLanguagePair == pair {
            return session
        }
        
        guard let source = pair.source else {
            throw TranslationError.sessionCreationFailed
        }
        
        // Neue Session erstellen (Apple Translation API ab macOS 26)
        let session = TranslationSession(installedSource: source, target: pair.target)
        
        translationSession = session
        currentLanguagePair = pair
        
        return session
    }
    
    private func detectSourceLocale(for text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        guard let language = recognizer.dominantLanguage else {
            return nil
        }
        
        return Locale.Language(identifier: language.rawValue)
    }
    
    private func makeCacheKey(text: String, target: Language, source: Language?) -> String {
        let sourceKey = source?.rawValue ?? "auto"
        return "\(sourceKey)_\(target.rawValue)_\(text.hashValue)"
    }
    
    private func cacheResult(_ result: TranslationResult, key: String) {
        // Cache-Größe begrenzen (FIFO)
        if translationCache.count >= maxCacheSize {
            if let firstKey = translationCache.keys.first {
                translationCache.removeValue(forKey: firstKey)
            }
        }
        translationCache[key] = result
    }
}

// MARK: - Errors

public enum TranslationError: LocalizedError {
    case emptyText
    case languageNotSupported(Language)
    case languagePairNotAvailable(source: Language, target: Language)
    case translationFailed(Error)
    case sessionCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Der zu übersetzende Text darf nicht leer sein."
        case .languageNotSupported(let language):
            return "Die Sprache '\(language.displayName)' wird nicht unterstützt."
        case .languagePairNotAvailable(let source, let target):
            return "Übersetzung von \(source.displayName) nach \(target.displayName) ist nicht verfügbar."
        case .translationFailed(let error):
            return "Übersetzung fehlgeschlagen: \(error.localizedDescription)"
        case .sessionCreationFailed:
            return "Übersetzungssession konnte nicht erstellt werden."
        }
    }
}

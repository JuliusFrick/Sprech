//
//  Language.swift
//  Sprech
//
//  Unterstützte Sprachen für Übersetzung
//

import Foundation

/// Unterstützte Sprachen für die Übersetzungsfunktion
public enum Language: String, CaseIterable, Codable, Sendable, Identifiable {
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    
    public var id: String { rawValue }
    
    /// Locale-Objekt für diese Sprache
    public var locale: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
    
    /// Anzeigename der Sprache (lokalisiert)
    public var displayName: String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: rawValue) ?? rawValue
    }
    
    /// Anzeigename der Sprache in der eigenen Sprache
    public var nativeName: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        }
    }
    
    /// Emoji-Flagge für die Sprache
    public var flag: String {
        switch self {
        case .german: return "🇩🇪"
        case .english: return "🇬🇧"
        case .french: return "🇫🇷"
        case .spanish: return "🇪🇸"
        case .italian: return "🇮🇹"
        }
    }
    
    /// Erstellt Language aus einem Locale-Language-Objekt
    public static func from(locale: Locale.Language) -> Language? {
        let code = locale.languageCode?.identifier ?? ""
        return Language(rawValue: code)
    }
    
    /// Alle Sprachen außer der angegebenen (für Zielsprachauswahl)
    public static func allExcept(_ language: Language) -> [Language] {
        allCases.filter { $0 != language }
    }
}

//
//  TranscriptionSettings.swift
//  Sprech
//
//  Settings Model für Transcription Provider
//

import Foundation

/// Settings für die Transkription
public final class TranscriptionSettings: ObservableObject, Codable {
    
    // MARK: - Keys
    
    private enum Keys {
        static let settings = "transcription_settings"
    }
    
    // MARK: - Properties
    
    /// ID des ausgewählten Providers
    @Published public var selectedProviderId: String
    
    /// Ausgewählte Sprache (Locale Identifier)
    @Published public var selectedLocale: String
    
    /// Bevorzuge nur Offline-Provider
    @Published public var preferOfflineOnly: Bool
    
    /// Automatisch Modelle herunterladen
    @Published public var autoDownloadModels: Bool
    
    /// Interpunktion aktivieren
    @Published public var enablePunctuation: Bool
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case selectedProviderId
        case selectedLocale
        case preferOfflineOnly
        case autoDownloadModels
        case enablePunctuation
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProviderId = try container.decode(String.self, forKey: .selectedProviderId)
        selectedLocale = try container.decode(String.self, forKey: .selectedLocale)
        preferOfflineOnly = try container.decode(Bool.self, forKey: .preferOfflineOnly)
        autoDownloadModels = try container.decode(Bool.self, forKey: .autoDownloadModels)
        enablePunctuation = try container.decode(Bool.self, forKey: .enablePunctuation)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProviderId, forKey: .selectedProviderId)
        try container.encode(selectedLocale, forKey: .selectedLocale)
        try container.encode(preferOfflineOnly, forKey: .preferOfflineOnly)
        try container.encode(autoDownloadModels, forKey: .autoDownloadModels)
        try container.encode(enablePunctuation, forKey: .enablePunctuation)
    }
    
    // MARK: - Initialization
    
    /// Standardwerte
    public init() {
        self.selectedProviderId = "apple-speech"
        self.selectedLocale = "de-DE"
        self.preferOfflineOnly = true
        self.autoDownloadModels = false
        self.enablePunctuation = true
    }
    
    /// Initialisierung mit Werten
    public init(
        selectedProviderId: String,
        selectedLocale: String,
        preferOfflineOnly: Bool,
        autoDownloadModels: Bool,
        enablePunctuation: Bool
    ) {
        self.selectedProviderId = selectedProviderId
        self.selectedLocale = selectedLocale
        self.preferOfflineOnly = preferOfflineOnly
        self.autoDownloadModels = autoDownloadModels
        self.enablePunctuation = enablePunctuation
    }
    
    // MARK: - Persistence
    
    /// Lädt Settings aus UserDefaults
    public static func load() -> TranscriptionSettings {
        guard let data = UserDefaults.standard.data(forKey: Keys.settings),
              let settings = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) else {
            return TranscriptionSettings()
        }
        return settings
    }
    
    /// Speichert Settings in UserDefaults
    public func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Keys.settings)
    }
    
    /// Setzt auf Standardwerte zurück
    public func reset() {
        selectedProviderId = "apple-speech"
        selectedLocale = "de-DE"
        preferOfflineOnly = true
        autoDownloadModels = false
        enablePunctuation = true
        save()
    }
}

// MARK: - Convenience

extension TranscriptionSettings {
    
    /// Locale Objekt für die ausgewählte Sprache
    public var locale: Locale {
        Locale(identifier: selectedLocale)
    }
    
    /// Verfügbare Sprachen (statisch)
    public static let availableLanguages: [(code: String, name: String)] = [
        ("de-DE", "🇩🇪 Deutsch"),
        ("en-US", "🇺🇸 Englisch (US)"),
        ("en-GB", "🇬🇧 Englisch (UK)"),
        ("fr-FR", "🇫🇷 Französisch"),
        ("es-ES", "🇪🇸 Spanisch"),
        ("it-IT", "🇮🇹 Italienisch"),
        ("pt-BR", "🇧🇷 Portugiesisch"),
        ("nl-NL", "🇳🇱 Niederländisch"),
        ("pl-PL", "🇵🇱 Polnisch"),
        ("ja-JP", "🇯🇵 Japanisch"),
        ("zh-CN", "🇨🇳 Chinesisch"),
    ]
}

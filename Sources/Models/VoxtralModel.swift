//
//  VoxtralModel.swift
//  Sprech
//
//  Voxtral Model Configuration - Mistral's Speech Recognition
//  MLX-konvertierte Modelle für lokale Inference auf Apple Silicon
//

import Foundation

// MARK: - Voxtral Model Variants

/// Verfügbare Voxtral-Modellvarianten
public enum VoxtralModelVariant: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Voxtral Mini 3B - Optimiert für lokale/Edge-Nutzung
    /// Gut für allgemeine Transkription, schnell auf M1+
    case mini3B = "voxtral-mini-3b"
    
    /// Voxtral Mini 4B Realtime - Streaming-optimiert
    /// Für Echtzeit-Transkription mit niedriger Latenz
    case mini4BRealtime = "voxtral-mini-4b-realtime"
    
    /// Voxtral Small 24B - Höchste Qualität
    /// Für beste Genauigkeit, benötigt mehr RAM (empfohlen: 32GB+)
    case small24B = "voxtral-small-24b"
    
    public var id: String { rawValue }
    
    // MARK: - Model Properties
    
    /// HuggingFace Repository ID für MLX-Version
    public var mlxRepositoryId: String {
        switch self {
        case .mini3B:
            return "mlx-community/Voxtral-Mini-3B-2507-bf16"
        case .mini4BRealtime:
            return "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
        case .small24B:
            // 24B noch nicht als MLX verfügbar - Placeholder
            return "mlx-community/Voxtral-Small-24B-2507-bf16"
        }
    }
    
    /// Original Mistral Repository (für Referenz)
    public var originalRepositoryId: String {
        switch self {
        case .mini3B:
            return "mistralai/Voxtral-Mini-3B-2507"
        case .mini4BRealtime:
            return "mistralai/Voxtral-Mini-4B-Realtime-2602"
        case .small24B:
            return "mistralai/Voxtral-Small-24B-2507"
        }
    }
    
    /// Anzeigeame für UI
    public var displayName: String {
        switch self {
        case .mini3B:
            return "Voxtral Mini (3B)"
        case .mini4BRealtime:
            return "Voxtral Realtime (4B)"
        case .small24B:
            return "Voxtral Small (24B)"
        }
    }
    
    /// Beschreibung für UI
    public var description: String {
        switch self {
        case .mini3B:
            return "Schnell & effizient - Ideal für Alltagsnutzung"
        case .mini4BRealtime:
            return "Streaming-optimiert - Niedrige Latenz für Live-Transkription"
        case .small24B:
            return "Höchste Genauigkeit - Benötigt 32GB+ RAM"
        }
    }
    
    /// Ungefähre Modellgröße in GB (Download)
    public var downloadSizeGB: Double {
        switch self {
        case .mini3B:
            return 6.0  // ~5B params bf16
        case .mini4BRealtime:
            return 8.0  // ~4B params fp16
        case .small24B:
            return 48.0 // ~24B params bf16
        }
    }
    
    /// Ungefährer RAM-Bedarf für Inference in GB
    public var requiredRAMGB: Int {
        switch self {
        case .mini3B:
            return 8
        case .mini4BRealtime:
            return 12
        case .small24B:
            return 32
        }
    }
    
    /// Ob das MLX-Modell aktuell verfügbar ist
    public var isMLXAvailable: Bool {
        switch self {
        case .mini3B, .mini4BRealtime:
            return true
        case .small24B:
            return false // Noch nicht konvertiert
        }
    }
    
    /// Ob Realtime-Streaming unterstützt wird
    public var supportsStreaming: Bool {
        self == .mini4BRealtime
    }
    
    /// Empfohlenes Modell basierend auf verfügbarem RAM
    public static func recommended(forRAMGB ram: Int) -> VoxtralModelVariant {
        if ram >= 32 {
            return .small24B
        } else if ram >= 12 {
            return .mini4BRealtime
        } else {
            return .mini3B
        }
    }
}

// MARK: - Supported Languages

/// Von Voxtral unterstützte Sprachen für Transkription
public enum VoxtralLanguage: String, CaseIterable, Identifiable, Sendable, Codable {
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"
    
    public var id: String { rawValue }
    
    /// Anzeigename auf Deutsch
    public var displayName: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "Englisch"
        case .french: return "Französisch"
        case .spanish: return "Spanisch"
        case .italian: return "Italienisch"
        case .portuguese: return "Portugiesisch"
        case .dutch: return "Niederländisch"
        case .polish: return "Polnisch"
        case .russian: return "Russisch"
        case .chinese: return "Chinesisch"
        case .japanese: return "Japanisch"
        case .korean: return "Koreanisch"
        case .arabic: return "Arabisch"
        case .hindi: return "Hindi"
        }
    }
    
    /// Native Sprachname
    public var nativeName: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .russian: return "Русский"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        }
    }
    
    /// BCP-47 Locale Identifier
    public var localeIdentifier: String {
        switch self {
        case .german: return "de-DE"
        case .english: return "en-US"
        case .french: return "fr-FR"
        case .spanish: return "es-ES"
        case .italian: return "it-IT"
        case .portuguese: return "pt-PT"
        case .dutch: return "nl-NL"
        case .polish: return "pl-PL"
        case .russian: return "ru-RU"
        case .chinese: return "zh-CN"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .arabic: return "ar-SA"
        case .hindi: return "hi-IN"
        }
    }
}

// MARK: - Model Status

/// Status des Voxtral-Modells
public enum VoxtralModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case error(String)
    
    public var isUsable: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var displayText: String {
        switch self {
        case .notDownloaded:
            return "Nicht heruntergeladen"
        case .downloading(let progress):
            return "Lade... \(Int(progress * 100))%"
        case .downloaded:
            return "Heruntergeladen"
        case .loading:
            return "Wird geladen..."
        case .ready:
            return "Bereit"
        case .error(let message):
            return "Fehler: \(message)"
        }
    }
}

// MARK: - Model Configuration

/// Konfiguration für Voxtral-Inference
public struct VoxtralConfiguration: Sendable, Codable {
    /// Ausgewählte Modellvariante
    public var modelVariant: VoxtralModelVariant
    
    /// Primäre Transkriptionssprache
    public var language: VoxtralLanguage
    
    /// Automatische Spracherkennung aktivieren
    public var autoDetectLanguage: Bool
    
    /// Satzzeichen hinzufügen
    public var addPunctuation: Bool
    
    /// Streaming/Realtime-Modus (falls unterstützt)
    public var enableStreaming: Bool
    
    /// Temperatur für Sampling (0.0 = deterministisch)
    public var temperature: Float
    
    /// Maximale Segmentlänge in Sekunden
    public var maxSegmentLength: TimeInterval
    
    public init(
        modelVariant: VoxtralModelVariant = .mini3B,
        language: VoxtralLanguage = .german,
        autoDetectLanguage: Bool = false,
        addPunctuation: Bool = true,
        enableStreaming: Bool = false,
        temperature: Float = 0.0,
        maxSegmentLength: TimeInterval = 30.0
    ) {
        self.modelVariant = modelVariant
        self.language = language
        self.autoDetectLanguage = autoDetectLanguage
        self.addPunctuation = addPunctuation
        self.enableStreaming = enableStreaming
        self.temperature = temperature
        self.maxSegmentLength = maxSegmentLength
    }
    
    /// Standard-Konfiguration für Deutsch
    public static let germanDefault = VoxtralConfiguration(
        modelVariant: .mini3B,
        language: .german,
        autoDetectLanguage: false,
        addPunctuation: true
    )
}

// MARK: - HuggingFace URLs

extension VoxtralModelVariant {
    /// Direkte Download-URL für das Modell
    public var downloadURL: URL? {
        URL(string: "https://huggingface.co/\(mlxRepositoryId)/resolve/main/")
    }
    
    /// HuggingFace Webseite
    public var huggingFaceURL: URL? {
        URL(string: "https://huggingface.co/\(mlxRepositoryId)")
    }
    
    /// Lokaler Speicherpfad
    public var localPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Sprech", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Voxtral", isDirectory: true)
            .appendingPathComponent(rawValue, isDirectory: true)
    }
}

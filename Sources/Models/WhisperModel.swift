//
//  WhisperModel.swift
//  Sprech
//
//  Whisper MLX Modellvarianten für lokale Spracherkennung
//

import Foundation

/// Verfügbare Whisper-Modellvarianten für MLX
public enum WhisperModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case tiny = "whisper-tiny"
    case base = "whisper-base"
    case small = "whisper-small"
    case medium = "whisper-medium"
    
    public var id: String { rawValue }
    
    // MARK: - Model Metadata
    
    /// Anzeigename des Modells
    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (Schnell)"
        case .base: return "Base (Ausgewogen)"
        case .small: return "Small (Genau)"
        case .medium: return "Medium (Hochpräzise)"
        }
    }
    
    /// Geschätzte Downloadgröße in Bytes
    public var downloadSize: Int64 {
        switch self {
        case .tiny: return 75 * 1024 * 1024      // ~75 MB
        case .base: return 150 * 1024 * 1024     // ~150 MB
        case .small: return 500 * 1024 * 1024    // ~500 MB
        case .medium: return 1536 * 1024 * 1024  // ~1.5 GB
        }
    }
    
    /// Formatierte Größenangabe
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: downloadSize)
    }
    
    /// HuggingFace Repository ID (mlx-community)
    public var huggingFaceRepo: String {
        "mlx-community/\(rawValue)-mlx"
    }
    
    /// Download-URL für das Modell
    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main")!
    }
    
    /// Erforderliche Dateien für das Modell
    public var requiredFiles: [String] {
        [
            "weights.npz",
            "config.json",
            "tokenizer.json",
            "mel_filters.npz"
        ]
    }
    
    /// Relative Genauigkeit (0.0 - 1.0)
    public var accuracy: Float {
        switch self {
        case .tiny: return 0.65
        case .base: return 0.75
        case .small: return 0.85
        case .medium: return 0.95
        }
    }
    
    /// Relative Geschwindigkeit (höher = schneller)
    public var speed: Float {
        switch self {
        case .tiny: return 1.0
        case .base: return 0.7
        case .small: return 0.4
        case .medium: return 0.2
        }
    }
    
    /// Empfohlenes Modell basierend auf verfügbarem RAM
    public static func recommended(availableRAM: Int64) -> WhisperModel {
        // RAM in GB
        let ramGB = availableRAM / (1024 * 1024 * 1024)
        
        if ramGB >= 16 {
            return .medium
        } else if ramGB >= 8 {
            return .small
        } else if ramGB >= 4 {
            return .base
        } else {
            return .tiny
        }
    }
}

// MARK: - Supported Languages

extension WhisperModel {
    
    /// Unterstützte Sprachen für Whisper
    public enum WhisperLanguage: String, CaseIterable, Codable, Sendable {
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
        case turkish = "tr"
        case swedish = "sv"
        case danish = "da"
        case norwegian = "no"
        case finnish = "fi"
        case czech = "cs"
        case hungarian = "hu"
        case romanian = "ro"
        case greek = "el"
        case ukrainian = "uk"
        case hebrew = "he"
        case thai = "th"
        case vietnamese = "vi"
        case indonesian = "id"
        case malay = "ms"
        
        /// Standard-Sprache: Deutsch
        public static let `default`: WhisperLanguage = .german
        
        /// Anzeigename
        public var displayName: String {
            let locale = Locale.current
            return locale.localizedString(forLanguageCode: rawValue) ?? rawValue
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
            case .turkish: return "Türkçe"
            case .swedish: return "Svenska"
            case .danish: return "Dansk"
            case .norwegian: return "Norsk"
            case .finnish: return "Suomi"
            case .czech: return "Čeština"
            case .hungarian: return "Magyar"
            case .romanian: return "Română"
            case .greek: return "Ελληνικά"
            case .ukrainian: return "Українська"
            case .hebrew: return "עברית"
            case .thai: return "ไทย"
            case .vietnamese: return "Tiếng Việt"
            case .indonesian: return "Bahasa Indonesia"
            case .malay: return "Bahasa Melayu"
            }
        }
        
        /// Whisper Language Token
        public var token: String {
            "<|\(rawValue)|>"
        }
    }
}

// MARK: - Model State

extension WhisperModel {
    
    /// Status eines heruntergeladenen Modells
    public enum ModelState: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case validating
        case invalid(reason: String)
        case loading
        case ready
        
        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
        
        public var isDownloaded: Bool {
            switch self {
            case .downloaded, .validating, .loading, .ready:
                return true
            default:
                return false
            }
        }
    }
}

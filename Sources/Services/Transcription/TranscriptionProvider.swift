//
//  TranscriptionProvider.swift
//  Sprech
//
//  Protocol für austauschbare Transcription Engines
//

import Foundation
import AVFoundation

// MARK: - Provider Status

/// Status eines Transcription Providers
public enum ProviderStatus: Sendable, Equatable {
    case ready
    case downloading(progress: Double)
    case needsDownload
    case unavailable(reason: String)
    case error(String)
    
    public var isAvailable: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var displayText: String {
        switch self {
        case .ready:
            return "Bereit"
        case .downloading(let progress):
            return "Download: \(Int(progress * 100))%"
        case .needsDownload:
            return "Download erforderlich"
        case .unavailable(let reason):
            return "Nicht verfügbar: \(reason)"
        case .error(let message):
            return "Fehler: \(message)"
        }
    }
}

// MARK: - Provider Configuration

/// Konfiguration für einen Provider
public struct ProviderConfiguration: Sendable {
    public let locale: Locale
    public let requiresOnDevice: Bool
    public let enablePunctuation: Bool
    
    public init(
        locale: Locale = Locale(identifier: "de-DE"),
        requiresOnDevice: Bool = true,
        enablePunctuation: Bool = true
    ) {
        self.locale = locale
        self.requiresOnDevice = requiresOnDevice
        self.enablePunctuation = enablePunctuation
    }
}

// MARK: - Provider Protocol

/// Protocol für Transcription Provider
/// Alle Provider müssen Sendable sein für Swift 6 Concurrency
public protocol TranscriptionProvider: Sendable {
    
    // MARK: - Identity
    
    /// Eindeutige ID des Providers
    var id: String { get }
    
    /// Anzeigename für UI
    var displayName: String { get }
    
    /// Beschreibung des Providers
    var description: String { get }
    
    // MARK: - Capabilities
    
    /// Ob der Provider offline funktioniert
    var isOfflineCapable: Bool { get }
    
    /// Ob ein Download erforderlich ist
    var requiresDownload: Bool { get }
    
    /// Größe des Downloads (nil wenn kein Download nötig)
    var downloadSize: String? { get }
    
    /// Unterstützte Sprachen
    var supportedLocales: [Locale] { get }
    
    // MARK: - Status
    
    /// Aktueller Status des Providers
    var status: ProviderStatus { get async }
    
    /// Prüft ob der Provider verfügbar ist
    var isAvailable: Bool { get async }
    
    // MARK: - Configuration
    
    /// Konfiguriert den Provider
    func configure(with configuration: ProviderConfiguration) async throws
    
    // MARK: - Transcription
    
    /// Transkribiert einen Audio-Buffer (einmalig)
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult
    
    /// Startet Streaming-Transkription
    func startStreaming() async throws -> AsyncStream<TranscriptionResult>
    
    /// Stoppt Streaming-Transkription
    func stopStreaming() async
    
    // MARK: - Model Management
    
    /// Lädt benötigte Modelle herunter
    func downloadModels(progressHandler: @escaping @Sendable (Double) -> Void) async throws
    
    /// Löscht heruntergeladene Modelle
    func deleteModels() async throws
}

// MARK: - Default Implementations

extension TranscriptionProvider {
    
    public var description: String {
        "\(displayName) Transcription Provider"
    }
    
    public var downloadSize: String? {
        nil
    }
    
    public func configure(with configuration: ProviderConfiguration) async throws {
        // Default: keine Konfiguration nötig
    }
    
    public func downloadModels(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        // Default: keine Downloads nötig
        progressHandler(1.0)
    }
    
    public func deleteModels() async throws {
        // Default: keine Modelle zu löschen
    }
}

// MARK: - Provider Errors

/// Fehler die bei Transcription auftreten können
public enum TranscriptionProviderError: Error, Sendable, LocalizedError {
    case providerNotAvailable
    case modelNotDownloaded
    case downloadFailed(String)
    case configurationFailed(String)
    case transcriptionFailed(String)
    case streamingNotSupported
    case localeNotSupported(String)
    case cancelled
    case notReady
    case invalidAudio
    
    public var errorDescription: String? {
        switch self {
        case .providerNotAvailable:
            return "Transcription Provider ist nicht verfügbar"
        case .modelNotDownloaded:
            return "Modell muss zuerst heruntergeladen werden"
        case .downloadFailed(let reason):
            return "Download fehlgeschlagen: \(reason)"
        case .configurationFailed(let reason):
            return "Konfiguration fehlgeschlagen: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transkription fehlgeschlagen: \(reason)"
        case .streamingNotSupported:
            return "Streaming wird von diesem Provider nicht unterstützt"
        case .localeNotSupported(let locale):
            return "Sprache '\(locale)' wird nicht unterstützt"
        case .cancelled:
            return "Transkription wurde abgebrochen"
        case .notReady:
            return "Provider ist nicht bereit"
        case .invalidAudio:
            return "Ungültige Audio-Daten"
        }
    }
}

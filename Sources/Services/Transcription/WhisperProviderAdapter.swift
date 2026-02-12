//
//  WhisperProviderAdapter.swift
//  Sprech
//
//  Adapter um WhisperMLXProvider mit TranscriptionProvider Protocol zu verbinden
//

import Foundation
import AVFoundation
import os.log

/// Adapter der WhisperMLXProvider als TranscriptionProvider verfügbar macht
public final class WhisperProviderAdapter: TranscriptionProvider, @unchecked Sendable {
    
    // MARK: - TranscriptionProvider Properties
    
    public let id = "whisper-mlx"
    public let displayName = "Whisper MLX"
    public let description = "Lokale Whisper-Modelle mit Apple Silicon Beschleunigung. Höchste Genauigkeit, komplett offline."
    public let isOfflineCapable = true
    public let requiresDownload = true
    
    public var downloadSize: String? {
        // Standard: Base Model
        return "145 MB"
    }
    
    public var supportedLocales: [Locale] {
        [
            Locale(identifier: "de-DE"),
            Locale(identifier: "en-US"),
            Locale(identifier: "en-GB"),
            Locale(identifier: "fr-FR"),
            Locale(identifier: "es-ES"),
            Locale(identifier: "it-IT"),
            Locale(identifier: "pt-BR"),
            Locale(identifier: "nl-NL"),
            Locale(identifier: "pl-PL"),
            Locale(identifier: "ja-JP"),
            Locale(identifier: "zh-CN"),
        ]
    }
    
    // MARK: - Private Properties
    
    @MainActor private var whisperProvider: WhisperMLXProvider?
    private let modelManager: MLXModelManager
    private let logger = Logger(subsystem: "com.sprech.app", category: "WhisperProviderAdapter")
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(modelManager: MLXModelManager = .shared) {
        self.modelManager = modelManager
    }
    
    // MARK: - Status
    
    public var status: ProviderStatus {
        get async {
            await MainActor.run {
                guard let provider = whisperProvider else {
                    // Prüfe ob Modell heruntergeladen ist
                    let model = WhisperModel.base
                    let modelDir = modelManager.modelDirectory(for: model)
                    let configFile = modelDir.appendingPathComponent("config.json")
                    
                    if FileManager.default.fileExists(atPath: configFile.path) {
                        return .ready
                    } else {
                        return .needsDownload
                    }
                }
                
                switch provider.state {
                case .ready:
                    return .ready
                case .downloading(let progress):
                    return .downloading(progress: progress)
                case .needsDownload:
                    return .needsDownload
                case .error:
                    return .error("Modell-Fehler")
                default:
                    return .unavailable(reason: provider.state.displayName)
                }
            }
        }
    }
    
    public var isAvailable: Bool {
        get async {
            await status.isAvailable
        }
    }
    
    // MARK: - Configuration
    
    public func configure(with configuration: ProviderConfiguration) async throws {
        try await MainActor.run {
            if whisperProvider == nil {
                whisperProvider = WhisperMLXProvider(modelManager: modelManager)
            }
            
            // Sprache setzen
            if let langCode = configuration.locale.identifier.split(separator: "-").first,
               let lang = WhisperModel.WhisperLanguage(rawValue: String(langCode)) {
                whisperProvider?.language = lang
            }
        }
        
        // Initialisieren
        try await MainActor.run {
            try await whisperProvider?.initialize()
        }
    }
    
    // MARK: - Transcription
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        try await MainActor.run {
            guard let provider = whisperProvider, provider.isReady else {
                throw TranscriptionProviderError.providerNotAvailable
            }
            
            return try await provider.transcribe(audioBuffer)
        }
    }
    
    public func startStreaming() async throws -> AsyncStream<TranscriptionResult> {
        try await MainActor.run {
            guard let provider = whisperProvider else {
                throw TranscriptionProviderError.providerNotAvailable
            }
            
            try await provider.startStreaming()
            return provider.partialResults
        }
    }
    
    public func stopStreaming() async {
        await MainActor.run {
            whisperProvider?.cancel()
        }
    }
    
    // MARK: - Model Management
    
    public func downloadModels(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        logger.info("Starte Download von Whisper-Modell...")
        
        await MainActor.run {
            if whisperProvider == nil {
                whisperProvider = WhisperMLXProvider(modelManager: modelManager)
            }
        }
        
        // Beobachte Download-Progress
        let model = WhisperModel.base
        
        try await modelManager.downloadModel(model)
        progressHandler(1.0)
        
        logger.info("Whisper-Modell Download abgeschlossen")
    }
    
    public func deleteModels() async throws {
        let model = WhisperModel.base
        let modelDir = modelManager.modelDirectory(for: model)
        
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        
        await MainActor.run {
            whisperProvider = nil
        }
        
        logger.info("Whisper-Modell gelöscht")
    }
}

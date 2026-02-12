//
//  VoxtralProvider.swift
//  Sprech
//
//  Voxtral Transcription Provider - Mistral's Speech Recognition
//  Komplett lokale Inference auf Apple Silicon via MLX
//
//  ⚠️ STATUS: PREVIEW / COMING SOON
//  Das MLX-Modell existiert (mlx-community/Voxtral-Mini-3B-2507-bf16),
//  aber mlx-audio-swift unterstützt aktuell nur TTS, nicht STT.
//  Sobald Swift-native STT verfügbar ist, wird dieser Provider aktiviert.
//

import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Voxtral Provider

/// Transkriptions-Provider für Voxtral (Mistral's Speech Model)
/// 
/// Voxtral ist Mistral's state-of-the-art Spracherkennungsmodell:
/// - 3B/4B/24B Varianten für verschiedene Hardware
/// - Mehrsprachig mit exzellentem Deutsch-Support
/// - Komplett lokal via MLX auf Apple Silicon
///
/// **Aktueller Status:** Preview - MLX-Modell verfügbar, Swift-Integration in Entwicklung
@MainActor
public final class VoxtralProvider: ObservableObject, TranscriptionProvider {
    
    // MARK: - TranscriptionProvider Protocol
    
    public let providerId = "voxtral"
    public let displayName = "Voxtral (Mistral)"
    public let isOffline = true
    
    public var isReady: Bool {
        if case .ready = status { return true }
        return false
    }
    
    public var supportedLanguages: [String] {
        VoxtralLanguage.allCases.map { $0.localeIdentifier }
    }
    
    public var currentLanguage: String {
        get { currentConfiguration.language.localeIdentifier }
        set {
            if let lang = VoxtralLanguage.allCases.first(where: { $0.localeIdentifier == newValue }) {
                currentConfiguration.language = lang
            }
        }
    }
    
    // MARK: - Published State
    
    @Published public private(set) var status: VoxtralProviderStatus = .uninitialized
    @Published public private(set) var modelStatus: VoxtralModelStatus = .notDownloaded
    @Published public var currentConfiguration: VoxtralConfiguration
    @Published public private(set) var isModelLoaded: Bool = false
    
    // MARK: - Streaming
    
    private var streamContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    
    public var partialResults: AsyncStream<TranscriptionResult> {
        AsyncStream { [weak self] continuation in
            self?.streamContinuation = continuation
        }
    }
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "VoxtralProvider")
    private var processor: VoxtralProcessor?
    
    /// Flag ob Swift-native MLX STT verfügbar ist
    /// TODO: Auf true setzen sobald mlx-audio-swift STT unterstützt
    private let isSwiftSTTAvailable = false
    
    // MARK: - Initialization
    
    public init(configuration: VoxtralConfiguration = .germanDefault) {
        self.currentConfiguration = configuration
        checkLocalModel()
    }
    
    // MARK: - Model Management
    
    private func checkLocalModel() {
        let modelPath = currentConfiguration.modelVariant.localPath
        if FileManager.default.fileExists(atPath: modelPath.path) {
            modelStatus = .downloaded
        } else {
            modelStatus = .notDownloaded
        }
    }
    
    /// Wechselt die Modellvariante
    public func setModelVariant(_ variant: VoxtralModelVariant) async throws {
        guard variant.isMLXAvailable else {
            throw TranscriptionProviderError.transcriptionFailed(
                "\(variant.displayName) ist noch nicht als MLX-Modell verfügbar"
            )
        }
        
        if isModelLoaded {
            processor = nil
            isModelLoaded = false
            status = .uninitialized
        }
        
        currentConfiguration.modelVariant = variant
        checkLocalModel()
        logger.info("Modellvariante gewechselt zu: \(variant.displayName)")
    }
    
    // MARK: - TranscriptionProvider Implementation
    
    public func initialize() async throws {
        logger.info("Initialisiere Voxtral Provider...")
        
        // Prüfe ob Swift STT verfügbar ist
        guard isSwiftSTTAvailable else {
            status = .unavailable(reason: "Swift-native MLX STT noch in Entwicklung")
            logger.warning("""
                ═══════════════════════════════════════════════════════
                VOXTRAL STATUS: COMING SOON
                ═══════════════════════════════════════════════════════
                
                Das MLX-Modell ist verfügbar:
                  \(self.currentConfiguration.modelVariant.mlxRepositoryId)
                
                Aber mlx-audio-swift unterstützt aktuell nur TTS, nicht STT.
                Sobald STT implementiert ist, wird Voxtral aktiviert.
                
                Alternativen:
                  • Apple Speech (sofort verfügbar)
                  • Whisper MLX (whisper-large-v3-mlx)
                
                HuggingFace: https://huggingface.co/\(self.currentConfiguration.modelVariant.mlxRepositoryId)
                ═══════════════════════════════════════════════════════
                """)
            throw TranscriptionProviderError.notInitialized
        }
        
        status = .initializing
        
        guard currentConfiguration.modelVariant.isMLXAvailable else {
            status = .unavailable(reason: "Modell nicht als MLX verfügbar")
            throw TranscriptionProviderError.transcriptionFailed("Modell nicht verfügbar")
        }
        
        if case .notDownloaded = modelStatus {
            try await downloadModel()
        }
        
        try await loadModel()
        status = .ready
        logger.info("Voxtral Provider bereit")
    }
    
    private func downloadModel() async throws {
        let variant = currentConfiguration.modelVariant
        logger.info("Starte Download: \(variant.mlxRepositoryId)")
        
        status = .downloadingModel(progress: 0.0)
        modelStatus = .downloading(progress: 0.0)
        
        // TODO: HuggingFace Download implementieren
        throw TranscriptionProviderError.transcriptionFailed(
            "Automatischer Download noch nicht implementiert. " +
            "Bitte manuell von \(variant.huggingFaceURL?.absoluteString ?? "HuggingFace") herunterladen."
        )
    }
    
    private func loadModel() async throws {
        status = .loadingModel
        modelStatus = .loading
        logger.info("Lade Voxtral Modell...")
        
        // TODO: MLX Model Loading mit mlx-audio-swift
        throw TranscriptionProviderError.transcriptionFailed("MLX Loading noch nicht implementiert")
    }
    
    // MARK: - Transcription
    
    public func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard isReady, let processor else {
            throw TranscriptionProviderError.notReady
        }
        
        status = .transcribing
        defer { status = .ready }
        
        let audioData = try bufferToData(buffer)
        let language = VoxtralLanguage.allCases.first { 
            $0.localeIdentifier == currentLanguage 
        } ?? .german
        
        logger.info("Transkribiere Audio in \(language.displayName)")
        
        return try await processor.transcribe(
            audioData: audioData,
            language: language,
            configuration: currentConfiguration
        )
    }
    
    public func transcribeFile(at url: URL) async throws -> TranscriptionResult {
        guard isReady, let processor else {
            throw TranscriptionProviderError.notReady
        }
        
        status = .transcribing
        defer { status = .ready }
        
        let audioData = try Data(contentsOf: url)
        let language = VoxtralLanguage.allCases.first { 
            $0.localeIdentifier == currentLanguage 
        } ?? .german
        
        return try await processor.transcribe(
            audioData: audioData,
            language: language,
            configuration: currentConfiguration
        )
    }
    
    // MARK: - Streaming
    
    public func startStreaming() async throws {
        guard currentConfiguration.modelVariant.supportsStreaming else {
            throw TranscriptionProviderError.streamingNotSupported
        }
        
        guard isReady else {
            throw TranscriptionProviderError.notReady
        }
        
        audioBuffers.removeAll()
        status = .streaming
        logger.info("Streaming gestartet")
    }
    
    public func appendAudio(_ buffer: AVAudioPCMBuffer) async throws {
        guard case .streaming = status else {
            throw TranscriptionProviderError.notReady
        }
        
        audioBuffers.append(buffer)
        
        // Partial result alle 5 Buffers
        if audioBuffers.count % 5 == 0 {
            // TODO: Partial inference
            let partialResult = TranscriptionResult(
                text: "[Partial...]",
                isFinal: false,
                confidence: 0.5
            )
            streamContinuation?.yield(partialResult)
        }
    }
    
    public func finishStreaming() async throws -> TranscriptionResult {
        defer {
            audioBuffers.removeAll()
            streamContinuation?.finish()
            streamContinuation = nil
            status = .ready
        }
        
        guard !audioBuffers.isEmpty else {
            return .empty
        }
        
        // Kombiniere alle Buffers
        let combinedData = try combineBuffers(audioBuffers)
        
        guard let processor else {
            throw TranscriptionProviderError.notReady
        }
        
        let language = VoxtralLanguage.allCases.first { 
            $0.localeIdentifier == currentLanguage 
        } ?? .german
        
        return try await processor.transcribe(
            audioData: combinedData,
            language: language,
            configuration: currentConfiguration
        )
    }
    
    public func cancel() {
        audioBuffers.removeAll()
        streamContinuation?.finish()
        streamContinuation = nil
        status = isModelLoaded ? .ready : .uninitialized
        logger.info("Transkription abgebrochen")
    }
    
    // MARK: - Audio Utilities
    
    private func bufferToData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let channelData = buffer.floatChannelData?[0] else {
            throw TranscriptionProviderError.invalidAudio
        }
        
        let frameLength = Int(buffer.frameLength)
        var data = Data(capacity: frameLength * MemoryLayout<Float>.size)
        
        for i in 0..<frameLength {
            var sample = channelData[i]
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        
        return data
    }
    
    private func combineBuffers(_ buffers: [AVAudioPCMBuffer]) throws -> Data {
        var combined = Data()
        for buffer in buffers {
            combined.append(try bufferToData(buffer))
        }
        return combined
    }
}

// MARK: - Voxtral Provider Status

public enum VoxtralProviderStatus: Sendable, Equatable {
    case uninitialized
    case initializing
    case downloadingModel(progress: Double)
    case loadingModel
    case ready
    case transcribing
    case streaming
    case unavailable(reason: String)
    
    public var displayText: String {
        switch self {
        case .uninitialized: return "Nicht initialisiert"
        case .initializing: return "Wird initialisiert..."
        case .downloadingModel(let p): return "Lade Modell... \(Int(p * 100))%"
        case .loadingModel: return "Lade in RAM..."
        case .ready: return "Bereit"
        case .transcribing: return "Transkribiere..."
        case .streaming: return "Streaming..."
        case .unavailable(let reason): return "Nicht verfügbar: \(reason)"
        }
    }
}

// MARK: - Availability Info

extension VoxtralProvider {
    
    public struct AvailabilityInfo: Sendable {
        public let isMLXModelAvailable: Bool
        public let isSwiftSTTAvailable: Bool
        public let mlxRepositoryId: String
        public let estimatedAvailability: String
        public let alternativeProviders: [String]
        
        public var statusMessage: String {
            if isSwiftSTTAvailable && isMLXModelAvailable {
                return "✅ Voxtral ist vollständig verfügbar"
            } else if isMLXModelAvailable {
                return "🔶 MLX-Modell verfügbar, Swift-Integration in Entwicklung"
            } else {
                return "❌ Voxtral MLX noch nicht verfügbar"
            }
        }
    }
    
    public var availabilityInfo: AvailabilityInfo {
        AvailabilityInfo(
            isMLXModelAvailable: currentConfiguration.modelVariant.isMLXAvailable,
            isSwiftSTTAvailable: isSwiftSTTAvailable,
            mlxRepositoryId: currentConfiguration.modelVariant.mlxRepositoryId,
            estimatedAvailability: "Wenn mlx-audio-swift STT unterstützt",
            alternativeProviders: ["Apple Speech (sofort)", "Whisper MLX"]
        )
    }
}

// MARK: - Preview

#if DEBUG
extension VoxtralProvider {
    static var preview: VoxtralProvider {
        VoxtralProvider(configuration: .germanDefault)
    }
}
#endif

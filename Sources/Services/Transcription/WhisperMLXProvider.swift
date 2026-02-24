//
//  WhisperMLXProvider.swift
//  Sprech
//
//  Lokaler Whisper-Provider mit MLX für Apple Silicon
//

import Foundation
import AVFoundation
import os.log
import Combine

// MLX Import (bedingt verfügbar)
#if canImport(MLX)
import MLX
import MLXRandom
#endif

/// Whisper-basierter Transkriptions-Provider mit MLX
@MainActor
public final class WhisperMLXProvider: ObservableObject {
    
    // MARK: - Legacy Properties (für Kompatibilität)
    
    public let providerId = "whisper-mlx"
    
    @Published public private(set) var isReady: Bool = false
    
    public var supportedLanguages: [String] {
        WhisperModel.WhisperLanguage.allCases.map { $0.rawValue }
    }
    
    public var currentLanguage: String {
        get { language.rawValue }
        set { 
            if let lang = WhisperModel.WhisperLanguage(rawValue: newValue) {
                language = lang
            }
        }
    }
    
    // MARK: - Published State
    
    @Published public private(set) var state: ProviderState = .uninitialized
    @Published public private(set) var loadedModel: WhisperModel?
    @Published public var selectedModel: WhisperModel = .base
    @Published public var language: WhisperModel.WhisperLanguage = .german
    
    // MARK: - Private Properties
    
    private let modelManager: MLXModelManager
    private var processor: WhisperProcessor?
    private var whisperModel: WhisperMLXModel?
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "WhisperMLXProvider")
    
    // Streaming State
    private var isStreaming = false
    private var streamingBuffer: [Float] = []
    private var partialResultsContinuation: AsyncStream<TranscriptionResult>.Continuation?
    
    // MARK: - Initialization
    
    public init(modelManager: MLXModelManager = .shared) {
        self.modelManager = modelManager
    }
    
    // MARK: - TranscriptionProvider Methods
    
    public func initialize() async throws {
        guard state == .uninitialized || state == .error else {
            logger.info("Provider bereits initialisiert")
            return
        }
        
        state = .initializing
        logger.info("Initialisiere WhisperMLXProvider...")
        
        // Prüfe ob Modell heruntergeladen ist
        let modelState = await modelManager.checkModelState(selectedModel)
        
        switch modelState {
        case .notDownloaded:
            state = .needsDownload
            throw TranscriptionProviderError.notReady
            
        case .downloaded, .ready:
            try await loadModel(selectedModel)
            
        case .downloading(let progress):
            state = .downloading(progress: progress)
            throw TranscriptionProviderError.notReady
            
        case .invalid(let reason):
            state = .error
            throw MLXModelError.loadingFailed(reason)
            
        default:
            break
        }
    }
    
    /// Lädt ein spezifisches Modell
    public func loadModel(_ model: WhisperModel) async throws {
        state = .loading
        logger.info("Lade Modell: \(model.rawValue)")
        
        let modelDir = modelManager.modelDirectory(for: model)
        
        // Processor initialisieren
        do {
            processor = try WhisperProcessor(modelDirectory: modelDir)
        } catch {
            state = .error
            throw MLXModelError.loadingFailed("Processor: \(error.localizedDescription)")
        }
        
        // MLX Model laden
        do {
            whisperModel = try await WhisperMLXModel.load(from: modelDir)
        } catch {
            state = .error
            throw MLXModelError.loadingFailed("Model: \(error.localizedDescription)")
        }
        
        loadedModel = model
        state = .ready
        isReady = true
        
        logger.info("Modell geladen: \(model.rawValue)")
    }
    
    /// Lädt Modell herunter und initialisiert
    public func downloadAndInitialize(_ model: WhisperModel) async throws {
        state = .downloading(progress: 0)
        
        // Beobachte Download-Progress
        let cancellable = modelManager.$downloadProgress
            .compactMap { $0[model] }
            .sink { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloading(progress: progress)
                }
            }
        
        defer { cancellable.cancel() }
        
        try await modelManager.downloadModel(model)
        selectedModel = model
        try await loadModel(model)
    }
    
    public func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard isReady, let processor = processor, let model = whisperModel else {
            throw TranscriptionProviderError.notReady
        }
        
        logger.debug("Transkribiere Buffer: \(buffer.frameLength) Samples")
        
        // Audio vorverarbeiten
        let samples = try processor.preprocessAudio(buffer)
        
        // Mel-Spektrogramm
        let melSpec = processor.melSpectrogram(samples)
        
        // Inference
        let tokens = try await model.transcribe(
            melSpectrogram: melSpec,
            language: language,
            processor: processor
        )
        
        // Dekodieren
        let text = processor.decodeTokens(tokens)
        
        return TranscriptionResult(
            text: text,
            isFinal: true,
            confidence: 0.9 // MLX gibt keine Confidence, schätzen
        )
    }
    
    public func transcribeFile(at url: URL) async throws -> TranscriptionResult {
        guard isReady else {
            throw TranscriptionProviderError.notReady
        }
        
        logger.info("Transkribiere Datei: \(url.lastPathComponent)")
        
        // Audio laden
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: WhisperProcessor.sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw TranscriptionProviderError.invalidAudio
        }
        
        try file.read(into: buffer)
        
        return try await transcribe(buffer)
    }
    
    // MARK: - Streaming
    
    public func startStreaming() async throws {
        guard isReady else {
            throw TranscriptionProviderError.notReady
        }
        
        isStreaming = true
        streamingBuffer = []
        
        logger.info("Streaming gestartet")
    }
    
    public func appendAudio(_ buffer: AVAudioPCMBuffer) async throws {
        guard isStreaming, let processor = processor else {
            throw TranscriptionProviderError.notReady
        }
        
        // Audio zu Buffer hinzufügen
        let samples = try processor.preprocessAudio(buffer)
        streamingBuffer.append(contentsOf: samples)
        
        // Wenn genug Samples für einen Chunk
        if streamingBuffer.count >= WhisperProcessor.samplesPerChunk / 2 {
            // Partial Transcription
            let partialResult = try await transcribeChunk(Array(streamingBuffer.suffix(WhisperProcessor.samplesPerChunk)))
            partialResultsContinuation?.yield(partialResult)
        }
    }
    
    public func finishStreaming() async throws -> TranscriptionResult {
        guard isStreaming, let processor = processor, let model = whisperModel else {
            throw TranscriptionProviderError.notReady
        }
        
        isStreaming = false
        
        logger.info("Streaming beendet, finalisiere...")
        
        // Finale Transkription des gesamten Buffers
        let melSpec = processor.melSpectrogram(streamingBuffer)
        let tokens = try await model.transcribe(
            melSpectrogram: melSpec,
            language: language,
            processor: processor
        )
        let text = processor.decodeTokens(tokens)
        
        streamingBuffer = []
        partialResultsContinuation?.finish()
        partialResultsContinuation = nil
        
        return TranscriptionResult(
            text: text,
            isFinal: true,
            confidence: 0.9
        )
    }
    
    public var partialResults: AsyncStream<TranscriptionResult> {
        AsyncStream { continuation in
            self.partialResultsContinuation = continuation
        }
    }
    
    public func cancel() {
        isStreaming = false
        streamingBuffer = []
        partialResultsContinuation?.finish()
        partialResultsContinuation = nil
        
        logger.info("Transkription abgebrochen")
    }
    
    // MARK: - Private Methods
    
    private func transcribeChunk(_ samples: [Float]) async throws -> TranscriptionResult {
        guard let processor = processor, let model = whisperModel else {
            throw TranscriptionProviderError.notReady
        }
        
        let melSpec = processor.melSpectrogram(samples)
        let tokens = try await model.transcribe(
            melSpectrogram: melSpec,
            language: language,
            processor: processor
        )
        let text = processor.decodeTokens(tokens)
        
        return TranscriptionResult(
            text: text,
            isFinal: false,
            confidence: 0.8
        )
    }
}

// MARK: - Provider State

extension WhisperMLXProvider {
    
    public enum ProviderState: Sendable, Equatable {
        case uninitialized
        case initializing
        case needsDownload
        case downloading(progress: Double)
        case loading
        case ready
        case error
        
        public var displayName: String {
            switch self {
            case .uninitialized: return "Nicht initialisiert"
            case .initializing: return "Initialisiere..."
            case .needsDownload: return "Modell wird benötigt"
            case .downloading(let progress): 
                return "Download: \(Int(progress * 100))%"
            case .loading: return "Lade Modell..."
            case .ready: return "Bereit"
            case .error: return "Fehler"
            }
        }
    }
}

// MARK: - MLX Whisper Model

/// Wrapper für das MLX Whisper-Modell
actor WhisperMLXModel {
    
    private let modelDirectory: URL
    private let config: WhisperModelConfig
    
    // MLX Tensoren würden hier gespeichert
    // In echter Implementierung mit mlx-swift
    
    private init(modelDirectory: URL, config: WhisperModelConfig) {
        self.modelDirectory = modelDirectory
        self.config = config
    }
    
    static func load(from directory: URL) async throws -> WhisperMLXModel {
        // Config laden
        let configURL = directory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(WhisperModelConfig.self, from: configData)
        
        // In echter Implementierung: MLX Weights laden
        // let weightsURL = directory.appendingPathComponent("weights.npz")
        // let weights = try MLX.loadNPZ(weightsURL)
        
        return WhisperMLXModel(modelDirectory: directory, config: config)
    }
    
    func transcribe(
        melSpectrogram: [[Float]],
        language: WhisperModel.WhisperLanguage,
        processor: WhisperProcessor
    ) async throws -> [Int] {
        // Encoder
        // let encoderOutput = try await runEncoder(melSpectrogram)
        
        // Decoder mit autoregressive Generation
        var tokens: [Int] = [
            processor.sotToken,
            processor.languageToken(for: language),
            processor.transcribeToken,
            processor.noTimestampsToken
        ]
        
        // Simulierte Token-Generierung
        // In echter Implementierung: MLX Inference
        // for _ in 0..<config.maxLength {
        //     let nextToken = try await decodeStep(encoderOutput, tokens)
        //     if nextToken == processor.tokenizer.eotToken { break }
        //     tokens.append(nextToken)
        // }
        
        // Platzhalter-Implementierung
        // Echte MLX-Inference würde hier stattfinden
        
        return tokens
    }
}

// MARK: - Config

struct WhisperModelConfig: Codable {
    let vocabSize: Int
    let numMelBins: Int
    let encoderLayers: Int
    let decoderLayers: Int
    let encoderAttentionHeads: Int
    let decoderAttentionHeads: Int
    let encoderDimension: Int
    let decoderDimension: Int
    let maxSourcePositions: Int
    let maxTargetPositions: Int
    
    var maxLength: Int { 448 }
    
    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case decoderLayers = "decoder_layers"
        case encoderAttentionHeads = "encoder_attention_heads"
        case decoderAttentionHeads = "decoder_attention_heads"
        case encoderDimension = "d_model"
        case decoderDimension = "decoder_dim"
        case maxSourcePositions = "max_source_positions"
        case maxTargetPositions = "max_target_positions"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vocabSize = try container.decode(Int.self, forKey: .vocabSize)
        numMelBins = try container.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 80
        encoderLayers = try container.decodeIfPresent(Int.self, forKey: .encoderLayers) ?? 4
        decoderLayers = try container.decodeIfPresent(Int.self, forKey: .decoderLayers) ?? 4
        encoderAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .encoderAttentionHeads) ?? 6
        decoderAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .decoderAttentionHeads) ?? 6
        encoderDimension = try container.decodeIfPresent(Int.self, forKey: .encoderDimension) ?? 384
        decoderDimension = try container.decodeIfPresent(Int.self, forKey: .decoderDimension) ?? 384
        maxSourcePositions = try container.decodeIfPresent(Int.self, forKey: .maxSourcePositions) ?? 1500
        maxTargetPositions = try container.decodeIfPresent(Int.self, forKey: .maxTargetPositions) ?? 448
    }
}

//
//  AppleSpeechProvider.swift
//  Sprech
//
//  Apple Speech Framework Provider - Wrapper um SpeechRecognitionService
//

import Foundation
import Speech
import AVFoundation
import os.log

/// Provider der Apple's eingebaute Spracherkennung verwendet
public final class AppleSpeechProvider: TranscriptionProvider, @unchecked Sendable {
    
    // MARK: - TranscriptionProvider Properties
    
    public let id = "apple-speech"
    public let displayName = "Apple Spracherkennung"
    public let description = "Schnelle, lokale Verarbeitung mit Apple's eingebauter Spracherkennung. Datenschutzfreundlich - deine Aufnahmen verlassen nie dein Gerät."
    public let isOfflineCapable = true
    public let requiresDownload = false
    
    public var supportedLocales: [Locale] {
        Array(SFSpeechRecognizer.supportedLocales())
    }
    
    // MARK: - Private Properties
    
    private let audioManager: AudioSessionManager
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentConfiguration: ProviderConfiguration?
    private var isStreaming = false
    private var streamContinuation: AsyncStream<TranscriptionResult>.Continuation?
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "AppleSpeechProvider")
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(audioManager: AudioSessionManager = .shared) {
        self.audioManager = audioManager
    }
    
    // MARK: - Status
    
    public var status: ProviderStatus {
        get async {
            // Prüfe Autorisierung
            let authStatus = SFSpeechRecognizer.authorizationStatus()
            
            switch authStatus {
            case .notDetermined:
                return .unavailable(reason: "Berechtigung nicht erteilt")
            case .denied:
                return .unavailable(reason: "Berechtigung verweigert")
            case .restricted:
                return .unavailable(reason: "Eingeschränkt")
            case .authorized:
                // Prüfe ob Recognizer verfügbar
                let locale = currentConfiguration?.locale ?? Locale(identifier: "de-DE")
                if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                    return .ready
                } else {
                    return .unavailable(reason: "Spracherkennung nicht verfügbar")
                }
            @unknown default:
                return .unavailable(reason: "Unbekannter Status")
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
        lock.lock()
        defer { lock.unlock() }
        
        // Prüfe ob Sprache unterstützt wird
        guard SFSpeechRecognizer.supportedLocales().contains(configuration.locale) else {
            throw TranscriptionProviderError.localeNotSupported(configuration.locale.identifier)
        }
        
        // Erstelle Recognizer
        speechRecognizer = SFSpeechRecognizer(locale: configuration.locale)
        currentConfiguration = configuration
        
        guard let recognizer = speechRecognizer else {
            throw TranscriptionProviderError.configurationFailed("Spracherkenner konnte nicht erstellt werden")
        }
        
        // Prüfe On-Device Support wenn erforderlich
        if configuration.requiresOnDevice && !recognizer.supportsOnDeviceRecognition {
            logger.warning("On-Device Erkennung nicht verfügbar für \(configuration.locale.identifier), nutze Server-basiert")
        }
        
        logger.info("Provider konfiguriert für: \(configuration.locale.identifier)")
    }
    
    // MARK: - Transcription
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechAudioBufferRecognitionRequest()
            
            // Konfiguriere Request
            if let config = currentConfiguration {
                if recognizer.supportsOnDeviceRecognition && config.requiresOnDevice {
                    request.requiresOnDeviceRecognition = true
                }
                request.addsPunctuation = config.enablePunctuation
            }
            
            request.shouldReportPartialResults = false
            request.append(audioBuffer)
            request.endAudio()
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionProviderError.transcriptionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result, result.isFinal else {
                    continuation.resume(throwing: TranscriptionProviderError.transcriptionFailed("Kein Ergebnis"))
                    return
                }
                
                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        confidence: segment.confidence,
                        timestamp: segment.timestamp,
                        duration: segment.duration
                    )
                }
                
                let avgConfidence = segments.isEmpty ? 0.0 : segments.map(\.confidence).reduce(0, +) / Float(segments.count)
                
                let transcription = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    isFinal: true,
                    confidence: avgConfidence,
                    segments: segments
                )
                
                continuation.resume(returning: transcription)
            }
        }
    }
    
    // MARK: - Streaming
    
    public func startStreaming() async throws -> AsyncStream<TranscriptionResult> {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        // Stoppe eventuell laufendes Streaming
        await stopStreaming()
        
        lock.lock()
        isStreaming = true
        lock.unlock()
        
        // Konfiguriere Audio-Engine
        try audioManager.configureAudioEngine()
        
        // Erstelle Recognition Request
        let request = SFSpeechAudioBufferRecognitionRequest()
        
        if let config = currentConfiguration {
            if recognizer.supportsOnDeviceRecognition && config.requiresOnDevice {
                request.requiresOnDeviceRecognition = true
            }
            request.addsPunctuation = config.enablePunctuation
        }
        
        request.shouldReportPartialResults = true
        
        lock.lock()
        recognitionRequest = request
        lock.unlock()
        
        // Installiere Audio Tap
        let inputNode = audioManager.inputNode
        let recordingFormat = audioManager.recordingFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.lock.lock()
            self?.recognitionRequest?.append(buffer)
            self?.lock.unlock()
        }
        
        // Starte Audio-Engine
        try audioManager.startAudioEngine()
        
        return AsyncStream { continuation in
            self.lock.lock()
            self.streamContinuation = continuation
            self.lock.unlock()
            
            // Starte Recognition Task
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Streaming Fehler: \(error.localizedDescription)")
                    self.lock.lock()
                    self.streamContinuation?.finish()
                    self.lock.unlock()
                    return
                }
                
                guard let result = result else { return }
                
                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        confidence: segment.confidence,
                        timestamp: segment.timestamp,
                        duration: segment.duration
                    )
                }
                
                let avgConfidence = segments.isEmpty ? 0.0 : segments.map(\.confidence).reduce(0, +) / Float(segments.count)
                
                let transcription = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal,
                    confidence: avgConfidence,
                    segments: segments
                )
                
                self.lock.lock()
                self.streamContinuation?.yield(transcription)
                
                if result.isFinal {
                    self.streamContinuation?.finish()
                }
                self.lock.unlock()
            }
            
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopStreaming()
                }
            }
        }
    }
    
    public func stopStreaming() async {
        lock.lock()
        defer { lock.unlock() }
        
        guard isStreaming else { return }
        
        logger.info("Stoppe Streaming...")
        
        // Task beenden
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Request beenden
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Stream beenden
        streamContinuation?.finish()
        streamContinuation = nil
        
        // Audio-Engine stoppen
        audioManager.stopAudioEngine()
        
        isStreaming = false
        
        logger.info("Streaming gestoppt")
    }
    
    // MARK: - Authorization
    
    /// Fordert Spracherkennung-Berechtigung an
    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    /// Prüft ob On-Device Erkennung verfügbar ist
    public var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
}

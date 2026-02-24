//
//  SpeechRecognitionService.swift
//  Sprech
//
//  Apple Speech Framework Integration für Live-Transkription
//

import Foundation
import Speech
import AVFoundation
import os.log
import Combine

/// Service für Spracherkennung mit Apple Speech Framework
@MainActor
public final class SpeechRecognitionService: ObservableObject, Sendable {
    
    // MARK: - Published Properties
    
    @Published public private(set) var state: RecognitionState = .idle
    @Published public private(set) var currentTranscription: TranscriptionResult = .empty
    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var supportedLocales: [Locale] = []
    
    // MARK: - Private Properties
    
    private let audioManager: AudioSessionManager
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "SpeechRecognitionService")
    
    /// Primäre Sprache: Deutsch
    public static let defaultLocale = Locale(identifier: "de-DE")
    
    // MARK: - Initialization
    
    public init(audioManager: AudioSessionManager = .shared) {
        self.audioManager = audioManager
        setupRecognizer(locale: Self.defaultLocale)
        loadSupportedLocales()
    }
    
    // MARK: - Setup
    
    /// Konfiguriert den Spracherkenner für eine bestimmte Sprache
    private func setupRecognizer(locale: Locale) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        if let recognizer = speechRecognizer {
            logger.info("Spracherkenner initialisiert für: \(locale.identifier)")
            logger.info("On-Device verfügbar: \(recognizer.supportsOnDeviceRecognition)")
        } else {
            logger.error("Spracherkenner konnte nicht initialisiert werden für: \(locale.identifier)")
        }
    }
    
    /// Lädt unterstützte Sprachen
    private func loadSupportedLocales() {
        supportedLocales = Array(SFSpeechRecognizer.supportedLocales())
            .sorted { $0.identifier < $1.identifier }
    }
    
    /// Wechselt die Erkennungssprache
    public func setLocale(_ locale: Locale) throws {
        guard SFSpeechRecognizer.supportedLocales().contains(locale) else {
            throw SpeechRecognitionError.languageNotSupported(locale.identifier)
        }
        
        // Falls gerade aktiv, stoppen
        if state.isActive {
            stopRecognition()
        }
        
        setupRecognizer(locale: locale)
        logger.info("Sprache gewechselt zu: \(locale.identifier)")
    }
    
    // MARK: - Authorization
    
    /// Fordert alle benötigten Berechtigungen an
    public func requestAuthorization() async -> Bool {
        // 1. Spracherkennung-Berechtigung
        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            state = .error(.notAuthorized)
            return false
        }
        
        // 2. Mikrofon-Berechtigung
        let micAuthorized = await audioManager.requestMicrophonePermission()
        guard micAuthorized else {
            state = .error(.microphoneAccessDenied)
            return false
        }
        
        isAuthorized = true
        logger.info("Alle Berechtigungen erteilt")
        return true
    }
    
    /// Fordert Spracherkennung-Berechtigung an
    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authorized = status == .authorized
                Task { @MainActor in
                    self.isAuthorized = authorized
                }
                continuation.resume(returning: authorized)
            }
        }
    }
    
    /// Prüft den aktuellen Autorisierungsstatus
    public func checkAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
    
    // MARK: - Recognition Control
    
    /// Startet die Live-Transkription
    public func startRecognition() async throws {
        guard !state.isActive else {
            logger.warning("Erkennung läuft bereits")
            return
        }
        
        // Prüfe Autorisierung
        if !isAuthorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                throw SpeechRecognitionError.notAuthorized
            }
        }
        
        // Prüfe Verfügbarkeit
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error(.recognizerNotAvailable)
            throw SpeechRecognitionError.recognizerNotAvailable
        }
        
        state = .preparing
        logger.info("Starte Spracherkennung...")
        
        do {
            try await setupAndStartRecognition(recognizer: recognizer)
        } catch {
            state = .error(.audioEngineError(error.localizedDescription))
            throw error
        }
    }
    
    /// Richtet die Erkennung ein und startet sie
    private func setupAndStartRecognition(recognizer: SFSpeechRecognizer) async throws {
        // Audio-Engine konfigurieren
        try audioManager.configureAudioEngine()
        
        // Recognition Request erstellen
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let request = recognitionRequest else {
            throw SpeechRecognitionError.recognitionFailed("Request konnte nicht erstellt werden")
        }
        
        // On-Device Erkennung bevorzugen (Privatsphäre)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            logger.info("Verwende On-Device Erkennung")
        }
        
        // Partial Results für Live-Transkription
        request.shouldReportPartialResults = true
        
        // Task-based completion handler hinzufügen
        request.addsPunctuation = true
        
        // Audio Tap installieren
        let inputNode = audioManager.inputNode
        let recordingFormat = audioManager.recordingFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Audio-Level berechnen
            Task { @MainActor [weak self] in
                self?.calculateAudioLevel(buffer: buffer)
            }
        }
        
        // Audio-Engine starten
        try audioManager.startAudioEngine()
        
        // Recognition Task starten
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
        
        state = .listening
        logger.info("Spracherkennung aktiv")
    }
    
    /// Verarbeitet Erkennungsergebnisse
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            handleRecognitionError(error)
            return
        }
        
        guard let result = result else { return }
        
        // Transkription aktualisieren
        let segments = result.bestTranscription.segments.map { segment in
            TranscriptionSegment(
                text: segment.substring,
                confidence: segment.confidence,
                timestamp: segment.timestamp,
                duration: segment.duration
            )
        }
        
        let transcription = TranscriptionResult(
            text: result.bestTranscription.formattedString,
            isFinal: result.isFinal,
            confidence: segments.isEmpty ? 0.0 : segments.map(\.confidence).reduce(0, +) / Float(segments.count),
            segments: segments
        )
        
        currentTranscription = transcription
        
        if result.isFinal {
            logger.info("Finale Transkription: \(transcription.text)")
            state = .processing
        }
    }
    
    /// Behandelt Erkennungsfehler
    private func handleRecognitionError(_ error: Error) {
        logger.error("Erkennungsfehler: \(error.localizedDescription)")
        
        let speechError: SpeechRecognitionError
        
        if let nsError = error as NSError? {
            switch nsError.code {
            case 1: // Cancelled
                speechError = .cancelled
            case 203: // Rate limit
                speechError = .recognitionFailed("Rate Limit erreicht")
            case 301: // Not authorized
                speechError = .notAuthorized
            default:
                speechError = .recognitionFailed(error.localizedDescription)
            }
        } else {
            speechError = .unknown(error.localizedDescription)
        }
        
        state = .error(speechError)
        stopRecognition()
    }
    
    /// Stoppt die Spracherkennung
    public func stopRecognition() {
        logger.info("Stoppe Spracherkennung...")
        
        // Task beenden
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Request beenden
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Audio-Engine stoppen
        audioManager.stopAudioEngine()
        
        if case .error = state {
            // Fehler-Status beibehalten
        } else {
            state = .idle
        }
        
        logger.info("Spracherkennung gestoppt")
    }
    
    /// Pausiert die Erkennung
    public func pauseRecognition() {
        guard state == .listening else { return }
        
        recognitionTask?.cancel()
        audioManager.audioEngine.pause()
        state = .paused
        
        logger.info("Spracherkennung pausiert")
    }
    
    /// Setzt die Erkennung zurück
    public func reset() {
        stopRecognition()
        currentTranscription = .empty
        state = .idle
    }
    
    // MARK: - Audio Level
    
    /// Berechnet den Audio-Pegel aus dem Buffer
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        
        let average = sum / Float(frameLength)
        let level = min(1.0, average * 10) // Normalisieren
        
        audioManager.setInputLevel(level)
    }
    
    // MARK: - Async Stream API
    
    /// Startet Erkennung und gibt einen AsyncStream von Transkriptionen zurück
    public func transcriptionStream() -> AsyncStream<TranscriptionResult> {
        AsyncStream { continuation in
            let cancellable = self.$currentTranscription
                .dropFirst()
                .sink { result in
                    continuation.yield(result)
                    
                    if result.isFinal {
                        continuation.finish()
                    }
                }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
                Task { @MainActor in
                    self.stopRecognition()
                }
            }
        }
    }
    
    /// Führt eine einmalige Erkennung durch und gibt das Ergebnis zurück
    public func recognizeOnce(timeout: TimeInterval = 30.0) async throws -> TranscriptionResult {
        try await startRecognition()
        
        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var timeoutTask: Task<Void, Never>?
            
            // Timeout
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !Task.isCancelled {
                    cancellable?.cancel()
                    continuation.resume(returning: self.currentTranscription)
                    self.stopRecognition()
                }
            }
            
            // Auf finales Ergebnis warten
            cancellable = self.$currentTranscription
                .filter { $0.isFinal }
                .first()
                .sink { result in
                    timeoutTask?.cancel()
                    continuation.resume(returning: result)
                    self.stopRecognition()
                }
        }
    }
}

// MARK: - Convenience Extensions

extension SpeechRecognitionService {
    
    /// Prüft ob On-Device Erkennung verfügbar ist
    public var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
    
    /// Aktuelle Erkennungssprache
    public var currentLocale: Locale? {
        speechRecognizer?.locale
    }
    
    /// Prüft ob der Erkenner verfügbar ist
    public var isRecognizerAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
}

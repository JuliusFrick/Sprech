//
//  AudioSessionManager.swift
//  Sprech
//
//  Verwaltet Mikrofon-Zugriff und Audio Session Setup für macOS
//

import Foundation
import AVFoundation
import os.log

/// Verwaltet die Audio-Session und Mikrofon-Zugriff
@MainActor
public final class AudioSessionManager: ObservableObject, Sendable {
    
    // MARK: - Properties
    
    @Published public private(set) var hasMicrophonePermission: Bool = false
    @Published public private(set) var isAudioEngineRunning: Bool = false
    @Published public private(set) var currentInputDevice: String?
    @Published public private(set) var inputLevel: Float = 0.0
    
    public let audioEngine: AVAudioEngine
    private let logger = Logger(subsystem: "com.sprech.app", category: "AudioSessionManager")
    
    private var levelTimer: Timer?
    
    // MARK: - Singleton
    
    public static let shared = AudioSessionManager()
    
    // MARK: - Initialization
    
    public init() {
        self.audioEngine = AVAudioEngine()
        Task {
            await checkMicrophonePermission()
        }
    }
    
    deinit {
        levelTimer?.invalidate()
    }
    
    // MARK: - Permission Handling
    
    /// Prüft den aktuellen Mikrofon-Berechtigungsstatus
    public func checkMicrophonePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
            logger.info("Mikrofon-Berechtigung bereits erteilt")
            
        case .notDetermined:
            logger.info("Mikrofon-Berechtigung noch nicht angefragt")
            hasMicrophonePermission = false
            
        case .denied, .restricted:
            logger.warning("Mikrofon-Berechtigung verweigert oder eingeschränkt")
            hasMicrophonePermission = false
            
        @unknown default:
            hasMicrophonePermission = false
        }
    }
    
    /// Fordert Mikrofon-Berechtigung an
    public func requestMicrophonePermission() async -> Bool {
        logger.info("Fordere Mikrofon-Berechtigung an...")
        
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        
        await MainActor.run {
            hasMicrophonePermission = granted
        }
        
        if granted {
            logger.info("Mikrofon-Berechtigung erteilt")
        } else {
            logger.warning("Mikrofon-Berechtigung verweigert")
        }
        
        return granted
    }
    
    // MARK: - Audio Engine Management
    
    /// Konfiguriert die Audio-Engine für Spracherkennung
    public func configureAudioEngine() throws {
        guard hasMicrophonePermission else {
            throw SpeechRecognitionError.microphoneAccessDenied
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Prüfe ob das Format gültig ist
        guard recordingFormat.sampleRate > 0 else {
            throw SpeechRecognitionError.audioEngineError("Ungültiges Audio-Format")
        }
        
        // Aktualisiere aktuelles Input-Device
        updateCurrentInputDevice()
        
        logger.info("Audio-Engine konfiguriert: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) Kanäle")
    }
    
    /// Startet die Audio-Engine
    public func startAudioEngine() throws {
        guard !audioEngine.isRunning else {
            logger.debug("Audio-Engine läuft bereits")
            return
        }
        
        do {
            try audioEngine.start()
            isAudioEngineRunning = true
            startLevelMonitoring()
            logger.info("Audio-Engine gestartet")
        } catch {
            logger.error("Fehler beim Starten der Audio-Engine: \(error.localizedDescription)")
            throw SpeechRecognitionError.audioEngineError(error.localizedDescription)
        }
    }
    
    /// Stoppt die Audio-Engine
    public func stopAudioEngine() {
        guard audioEngine.isRunning else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isAudioEngineRunning = false
        stopLevelMonitoring()
        inputLevel = 0.0
        
        logger.info("Audio-Engine gestoppt")
    }
    
    /// Gibt die Audio-Engine Input Node zurück
    public var inputNode: AVAudioInputNode {
        audioEngine.inputNode
    }
    
    /// Gibt das Recording-Format zurück
    public var recordingFormat: AVAudioFormat {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }
    
    // MARK: - Input Device Management
    
    /// Aktualisiert das aktuelle Input-Device
    private func updateCurrentInputDevice() {
        #if os(macOS)
        // Auf macOS können wir die Audio-Devices abfragen
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        
        if let defaultDevice = devices.first {
            currentInputDevice = defaultDevice.localizedName
            logger.debug("Aktuelles Input-Device: \(defaultDevice.localizedName)")
        }
        #endif
    }
    
    /// Listet verfügbare Audio-Input-Devices auf
    public func availableInputDevices() -> [String] {
        #if os(macOS)
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        
        return devices.map { $0.localizedName }
        #else
        return []
        #endif
    }
    
    // MARK: - Level Monitoring
    
    /// Startet die Überwachung des Eingangspegels
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateInputLevel()
            }
        }
    }
    
    /// Stoppt die Überwachung des Eingangspegels
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    /// Aktualisiert den Eingangspegel
    private func updateInputLevel() {
        // Der tatsächliche Pegel wird durch den Tap in SpeechRecognitionService aktualisiert
        // Diese Methode dient als Platzhalter für UI-Updates
    }
    
    /// Setzt den Eingangspegel (aufgerufen vom SpeechRecognitionService)
    public func setInputLevel(_ level: Float) {
        inputLevel = level
    }
}

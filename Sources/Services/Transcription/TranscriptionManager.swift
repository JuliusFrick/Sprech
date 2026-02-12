//
//  TranscriptionManager.swift
//  Sprech
//
//  Verwaltet Transcription Provider und koordiniert Transkription
//

import Foundation
import AVFoundation
import Combine
import os.log

/// Manager für Transcription Provider
@MainActor
public final class TranscriptionManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TranscriptionManager()
    
    // MARK: - Published Properties
    
    /// Alle registrierten Provider
    @Published public private(set) var availableProviders: [any TranscriptionProvider] = []
    
    /// Aktuell ausgewählter Provider
    @Published public private(set) var selectedProvider: (any TranscriptionProvider)?
    
    /// Aktueller Status des ausgewählten Providers
    @Published public private(set) var selectedProviderStatus: ProviderStatus = .unavailable(reason: "Nicht initialisiert")
    
    /// Aktuelle Transkription
    @Published public private(set) var currentTranscription: TranscriptionResult = .empty
    
    /// Ob gerade transkribiert wird
    @Published public private(set) var isTranscribing: Bool = false
    
    /// Aktuelle Konfiguration
    @Published public var configuration: ProviderConfiguration {
        didSet {
            Task {
                await reconfigureProvider()
            }
        }
    }
    
    // MARK: - Settings
    
    private let settings: TranscriptionSettings
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "TranscriptionManager")
    private var streamTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        self.settings = TranscriptionSettings.load()
        self.configuration = ProviderConfiguration(
            locale: Locale(identifier: settings.selectedLocale),
            requiresOnDevice: settings.preferOfflineOnly,
            enablePunctuation: true
        )
        
        // Registriere Standard-Provider
        registerDefaultProviders()
        
        // Wähle gespeicherten Provider
        Task {
            await selectSavedProvider()
        }
    }
    
    // MARK: - Provider Registration
    
    /// Registriert die Standard-Provider
    private func registerDefaultProviders() {
        var providers: [any TranscriptionProvider] = []
        
        // Apple Speech (immer verfügbar)
        let appleSpeech = AppleSpeechProvider(audioManager: .shared)
        providers.append(appleSpeech)
        
        // MLX Whisper via Adapter
        let whisperAdapter = WhisperProviderAdapter(modelManager: .shared)
        providers.append(whisperAdapter)
        
        availableProviders = providers
        
        logger.info("Standard-Provider registriert: \(self.availableProviders.count)")
    }
    
    /// Registriert einen neuen Provider
    public func registerProvider(_ provider: any TranscriptionProvider) {
        // Prüfe ob Provider bereits registriert
        guard !availableProviders.contains(where: { $0.id == provider.id }) else {
            logger.warning("Provider \(provider.id) bereits registriert")
            return
        }
        
        availableProviders.append(provider)
        logger.info("Provider registriert: \(provider.displayName)")
    }
    
    /// Entfernt einen Provider
    public func unregisterProvider(id: String) {
        availableProviders.removeAll { $0.id == id }
        
        // Falls es der ausgewählte Provider war, wähle einen anderen
        if selectedProvider?.id == id {
            Task {
                await selectFirstAvailableProvider()
            }
        }
        
        logger.info("Provider entfernt: \(id)")
    }
    
    // MARK: - Provider Selection
    
    /// Wählt den gespeicherten Provider aus
    private func selectSavedProvider() async {
        let savedId = settings.selectedProviderId
        
        if let provider = availableProviders.first(where: { $0.id == savedId }) {
            await switchProvider(to: provider)
        } else {
            await selectFirstAvailableProvider()
        }
    }
    
    /// Wählt den ersten verfügbaren Provider
    private func selectFirstAvailableProvider() async {
        for provider in availableProviders {
            if await provider.isAvailable {
                await switchProvider(to: provider)
                return
            }
        }
        
        // Falls keiner verfügbar, wähle trotzdem den ersten
        if let first = availableProviders.first {
            await switchProvider(to: first)
        }
    }
    
    /// Wechselt zu einem anderen Provider
    public func switchProvider(to provider: any TranscriptionProvider) async {
        // Stoppe laufende Transkription
        await stopTranscription()
        
        selectedProvider = provider
        
        // Speichere Auswahl
        settings.selectedProviderId = provider.id
        settings.save()
        
        // Konfiguriere Provider
        await reconfigureProvider()
        
        logger.info("Provider gewechselt zu: \(provider.displayName)")
    }
    
    /// Wechselt zu einem Provider per ID
    public func switchProvider(toId id: String) async {
        guard let provider = availableProviders.first(where: { $0.id == id }) else {
            logger.error("Provider nicht gefunden: \(id)")
            return
        }
        
        await switchProvider(to: provider)
    }
    
    /// Konfiguriert den aktuellen Provider neu
    private func reconfigureProvider() async {
        guard let provider = selectedProvider else { return }
        
        do {
            try await provider.configure(with: configuration)
            selectedProviderStatus = await provider.status
        } catch {
            logger.error("Provider-Konfiguration fehlgeschlagen: \(error.localizedDescription)")
            selectedProviderStatus = .error(error.localizedDescription)
        }
    }
    
    // MARK: - Status Updates
    
    /// Aktualisiert den Status aller Provider
    public func refreshProviderStatus() async {
        if let provider = selectedProvider {
            selectedProviderStatus = await provider.status
        }
    }
    
    /// Holt den Status für einen bestimmten Provider
    public func status(for providerId: String) async -> ProviderStatus {
        guard let provider = availableProviders.first(where: { $0.id == providerId }) else {
            return .unavailable(reason: "Provider nicht gefunden")
        }
        return await provider.status
    }
    
    // MARK: - Transcription
    
    /// Transkribiert einen Audio-Buffer
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard let provider = selectedProvider else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        guard await provider.isAvailable else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        let result = try await provider.transcribe(audioBuffer: audioBuffer)
        currentTranscription = result
        
        return result
    }
    
    /// Startet Streaming-Transkription
    public func startStreaming() async throws {
        guard let provider = selectedProvider else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        guard await provider.isAvailable else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        // Stoppe eventuell laufendes Streaming
        await stopTranscription()
        
        isTranscribing = true
        
        let stream = try await provider.startStreaming()
        
        streamTask = Task {
            for await result in stream {
                await MainActor.run {
                    self.currentTranscription = result
                }
                
                if result.isFinal {
                    break
                }
            }
            
            await MainActor.run {
                self.isTranscribing = false
            }
        }
    }
    
    /// Stoppt die laufende Transkription
    public func stopTranscription() async {
        streamTask?.cancel()
        streamTask = nil
        
        if let provider = selectedProvider {
            await provider.stopStreaming()
        }
        
        isTranscribing = false
    }
    
    /// Setzt die aktuelle Transkription zurück
    public func reset() async {
        await stopTranscription()
        currentTranscription = .empty
    }
    
    // MARK: - Model Download
    
    /// Lädt Modelle für einen Provider herunter
    public func downloadModels(
        for providerId: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let provider = availableProviders.first(where: { $0.id == providerId }) else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        try await provider.downloadModels(progressHandler: progressHandler)
        
        // Status aktualisieren
        if providerId == selectedProvider?.id {
            selectedProviderStatus = await provider.status
        }
    }
    
    /// Löscht heruntergeladene Modelle
    public func deleteModels(for providerId: String) async throws {
        guard let provider = availableProviders.first(where: { $0.id == providerId }) else {
            throw TranscriptionProviderError.providerNotAvailable
        }
        
        try await provider.deleteModels()
        
        // Status aktualisieren
        if providerId == selectedProvider?.id {
            selectedProviderStatus = await provider.status
        }
    }
    
    // MARK: - Settings
    
    /// Aktualisiert die Sprache
    public func setLocale(_ locale: Locale) {
        settings.selectedLocale = locale.identifier
        settings.save()
        
        configuration = ProviderConfiguration(
            locale: locale,
            requiresOnDevice: settings.preferOfflineOnly,
            enablePunctuation: true
        )
    }
    
    /// Setzt Offline-Präferenz
    public func setPreferOfflineOnly(_ preferOffline: Bool) {
        settings.preferOfflineOnly = preferOffline
        settings.save()
        
        configuration = ProviderConfiguration(
            locale: Locale(identifier: settings.selectedLocale),
            requiresOnDevice: preferOffline,
            enablePunctuation: true
        )
    }
    
    /// Aktuelle Settings
    public var currentSettings: TranscriptionSettings {
        settings
    }
}

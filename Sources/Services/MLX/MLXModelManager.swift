//
//  MLXModelManager.swift
//  Sprech
//
//  Verwaltet Download, Caching und Validierung von MLX Whisper-Modellen
//

import Foundation
import os.log
import Combine

/// Manager für MLX Whisper-Modelle
@MainActor
public final class MLXModelManager: ObservableObject, Sendable {
    
    // MARK: - Singleton
    
    public static let shared = MLXModelManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var modelStates: [WhisperModel: WhisperModel.ModelState] = [:]
    @Published public private(set) var downloadProgress: [WhisperModel: Double] = [:]
    @Published public private(set) var currentDownload: WhisperModel?
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.sprech.app", category: "MLXModelManager")
    private let session: URLSession
    
    private var downloadTasks: [WhisperModel: URLSessionDownloadTask] = [:]
    private var progressObservations: [WhisperModel: NSKeyValueObservation] = [:]
    
    // MARK: - Paths
    
    /// Basis-Verzeichnis für Modelle
    public var modelsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Sprech/Models", isDirectory: true)
    }
    
    /// Verzeichnis für ein spezifisches Modell
    public func modelDirectory(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.rawValue, isDirectory: true)
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1 Stunde für große Modelle
        self.session = URLSession(configuration: config)
        
        // Initiale Statusprüfung
        Task {
            await refreshModelStates()
        }
    }
    
    // MARK: - Model State Management
    
    /// Aktualisiert den Status aller Modelle
    public func refreshModelStates() async {
        for model in WhisperModel.allCases {
            let state = await checkModelState(model)
            modelStates[model] = state
        }
    }
    
    /// Prüft den Status eines einzelnen Modells
    public func checkModelState(_ model: WhisperModel) async -> WhisperModel.ModelState {
        let modelDir = modelDirectory(for: model)
        
        // Prüfe ob Verzeichnis existiert
        guard fileManager.fileExists(atPath: modelDir.path) else {
            return .notDownloaded
        }
        
        // Prüfe ob alle erforderlichen Dateien vorhanden sind
        for file in model.requiredFiles {
            let filePath = modelDir.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: filePath.path) else {
                return .notDownloaded
            }
        }
        
        // Validiere Modell
        if await validateModel(model) {
            return .downloaded
        } else {
            return .invalid(reason: "Modelldateien sind beschädigt")
        }
    }
    
    // MARK: - Disk Space Check
    
    /// Prüft ob genug Speicherplatz für ein Modell verfügbar ist
    public func checkDiskSpace(for model: WhisperModel) throws -> Bool {
        let requiredSpace = model.downloadSize + (100 * 1024 * 1024) // + 100MB Puffer
        
        let resourceValues = try modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        
        guard let availableSpace = resourceValues.volumeAvailableCapacityForImportantUsage else {
            throw MLXModelError.diskSpaceCheckFailed
        }
        
        if availableSpace < requiredSpace {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let required = formatter.string(fromByteCount: requiredSpace)
            let available = formatter.string(fromByteCount: availableSpace)
            
            throw MLXModelError.insufficientDiskSpace(
                required: required,
                available: available
            )
        }
        
        return true
    }
    
    // MARK: - Download
    
    /// Lädt ein Modell von HuggingFace herunter
    public func downloadModel(_ model: WhisperModel) async throws {
        // Prüfe Speicherplatz
        _ = try checkDiskSpace(for: model)
        
        // Erstelle Modellverzeichnis
        let modelDir = modelDirectory(for: model)
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        currentDownload = model
        modelStates[model] = .downloading(progress: 0)
        downloadProgress[model] = 0
        
        logger.info("Starte Download: \(model.rawValue)")
        
        do {
            // Lade alle erforderlichen Dateien
            for (index, file) in model.requiredFiles.enumerated() {
                let fileURL = model.downloadURL.appendingPathComponent(file)
                let destinationURL = modelDir.appendingPathComponent(file)
                
                try await downloadFile(
                    from: fileURL,
                    to: destinationURL,
                    model: model,
                    fileIndex: index,
                    totalFiles: model.requiredFiles.count
                )
            }
            
            // Validiere heruntergeladenes Modell
            modelStates[model] = .validating
            
            if await validateModel(model) {
                modelStates[model] = .downloaded
                logger.info("Download abgeschlossen: \(model.rawValue)")
            } else {
                throw MLXModelError.validationFailed
            }
            
        } catch {
            // Cleanup bei Fehler
            try? fileManager.removeItem(at: modelDir)
            modelStates[model] = .notDownloaded
            throw error
        }
        
        currentDownload = nil
        downloadProgress[model] = nil
    }
    
    /// Lädt eine einzelne Datei herunter
    private func downloadFile(
        from url: URL,
        to destination: URL,
        model: WhisperModel,
        fileIndex: Int,
        totalFiles: Int
    ) async throws {
        logger.debug("Lade Datei: \(url.lastPathComponent)")
        
        let (tempURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MLXModelError.downloadFailed(url.lastPathComponent)
        }
        
        // Verschiebe in Zielverzeichnis
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        
        // Update Progress
        let baseProgress = Double(fileIndex) / Double(totalFiles)
        let fileProgress = 1.0 / Double(totalFiles)
        let totalProgress = baseProgress + fileProgress
        
        downloadProgress[model] = totalProgress
        modelStates[model] = .downloading(progress: totalProgress)
    }
    
    /// Bricht einen laufenden Download ab
    public func cancelDownload(_ model: WhisperModel) {
        downloadTasks[model]?.cancel()
        downloadTasks[model] = nil
        progressObservations[model]?.invalidate()
        progressObservations[model] = nil
        
        currentDownload = nil
        downloadProgress[model] = nil
        modelStates[model] = .notDownloaded
        
        // Lösche unvollständige Dateien
        let modelDir = modelDirectory(for: model)
        try? fileManager.removeItem(at: modelDir)
        
        logger.info("Download abgebrochen: \(model.rawValue)")
    }
    
    // MARK: - Validation
    
    /// Validiert ein heruntergeladenes Modell
    public func validateModel(_ model: WhisperModel) async -> Bool {
        let modelDir = modelDirectory(for: model)
        
        // Prüfe alle erforderlichen Dateien
        for file in model.requiredFiles {
            let filePath = modelDir.appendingPathComponent(file)
            
            guard fileManager.fileExists(atPath: filePath.path) else {
                logger.error("Fehlende Datei: \(file)")
                return false
            }
            
            // Prüfe Dateigröße (nicht leer)
            do {
                let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
                guard let size = attributes[.size] as? Int64, size > 0 else {
                    logger.error("Leere Datei: \(file)")
                    return false
                }
            } catch {
                logger.error("Fehler beim Prüfen: \(file) - \(error)")
                return false
            }
        }
        
        // Validiere config.json
        let configPath = modelDir.appendingPathComponent("config.json")
        do {
            let configData = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(WhisperConfig.self, from: configData)
            
            logger.debug("Modell validiert: \(model.rawValue), vocab_size: \(config.vocabSize)")
            return true
        } catch {
            logger.error("Config-Validierung fehlgeschlagen: \(error)")
            return false
        }
    }
    
    // MARK: - Model Management
    
    /// Löscht ein heruntergeladenes Modell
    public func deleteModel(_ model: WhisperModel) throws {
        let modelDir = modelDirectory(for: model)
        
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
            logger.info("Modell gelöscht: \(model.rawValue)")
        }
        
        modelStates[model] = .notDownloaded
    }
    
    /// Gibt den Speicherverbrauch aller Modelle zurück
    public func totalStorageUsed() -> Int64 {
        var total: Int64 = 0
        
        for model in WhisperModel.allCases {
            let modelDir = modelDirectory(for: model)
            guard fileManager.fileExists(atPath: modelDir.path) else { continue }
            
            if let enumerator = fileManager.enumerator(at: modelDir, includingPropertiesForKeys: [.fileSizeKey]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        
        return total
    }
    
    /// Formatierter Speicherverbrauch
    public var formattedStorageUsed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalStorageUsed())
    }
}

// MARK: - Whisper Config

/// Minimale Config-Struktur für Validierung
private struct WhisperConfig: Codable {
    let vocabSize: Int
    let numMelBins: Int?
    let encoderLayers: Int?
    let decoderLayers: Int?
    
    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case decoderLayers = "decoder_layers"
    }
}

// MARK: - Errors

/// Fehler beim Model-Management
public enum MLXModelError: Error, LocalizedError, Sendable {
    case modelNotFound(String)
    case downloadFailed(String)
    case validationFailed
    case insufficientDiskSpace(required: String, available: String)
    case diskSpaceCheckFailed
    case loadingFailed(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Modell '\(model)' wurde nicht gefunden"
        case .downloadFailed(let file):
            return "Download fehlgeschlagen: \(file)"
        case .validationFailed:
            return "Modellvalidierung fehlgeschlagen"
        case .insufficientDiskSpace(let required, let available):
            return "Nicht genug Speicherplatz. Benötigt: \(required), Verfügbar: \(available)"
        case .diskSpaceCheckFailed:
            return "Speicherplatzprüfung fehlgeschlagen"
        case .loadingFailed(let reason):
            return "Modell konnte nicht geladen werden: \(reason)"
        case .cancelled:
            return "Vorgang abgebrochen"
        }
    }
}

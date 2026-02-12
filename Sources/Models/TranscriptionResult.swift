//
//  TranscriptionResult.swift
//  Sprech
//
//  Model für Transkriptionsergebnisse
//

import Foundation

/// Repräsentiert ein Transkriptionsergebnis
@MainActor
public struct TranscriptionResult: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let isFinal: Bool
    public let confidence: Float
    public let timestamp: Date
    public let segments: [TranscriptionSegment]
    
    public init(
        id: UUID = UUID(),
        text: String,
        isFinal: Bool,
        confidence: Float = 0.0,
        timestamp: Date = Date(),
        segments: [TranscriptionSegment] = []
    ) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = timestamp
        self.segments = segments
    }
    
    /// Leeres Ergebnis
    public static let empty = TranscriptionResult(
        text: "",
        isFinal: false,
        confidence: 0.0
    )
}

/// Ein einzelnes Segment innerhalb einer Transkription
public struct TranscriptionSegment: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    
    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        timestamp: TimeInterval,
        duration: TimeInterval
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.timestamp = timestamp
        self.duration = duration
    }
}

/// Status der Spracherkennung
public enum RecognitionState: Sendable, Equatable {
    case idle
    case preparing
    case listening
    case processing
    case paused
    case error(SpeechRecognitionError)
    
    public var isActive: Bool {
        switch self {
        case .listening, .processing:
            return true
        default:
            return false
        }
    }
    
    public var displayName: String {
        switch self {
        case .idle:
            return "Bereit"
        case .preparing:
            return "Vorbereiten..."
        case .listening:
            return "Höre zu..."
        case .processing:
            return "Verarbeite..."
        case .paused:
            return "Pausiert"
        case .error(let error):
            return "Fehler: \(error.localizedDescription)"
        }
    }
}

/// Fehler bei der Spracherkennung
public enum SpeechRecognitionError: Error, Sendable, Equatable {
    case notAvailable
    case notAuthorized
    case microphoneAccessDenied
    case recognizerNotAvailable
    case audioEngineError(String)
    case recognitionFailed(String)
    case languageNotSupported(String)
    case cancelled
    case unknown(String)
    
    public var localizedDescription: String {
        switch self {
        case .notAvailable:
            return "Spracherkennung ist auf diesem Gerät nicht verfügbar"
        case .notAuthorized:
            return "Spracherkennung wurde nicht autorisiert"
        case .microphoneAccessDenied:
            return "Mikrofonzugriff wurde verweigert"
        case .recognizerNotAvailable:
            return "Spracherkenner ist nicht verfügbar"
        case .audioEngineError(let message):
            return "Audio-Engine Fehler: \(message)"
        case .recognitionFailed(let message):
            return "Erkennung fehlgeschlagen: \(message)"
        case .languageNotSupported(let language):
            return "Sprache '\(language)' wird nicht unterstützt"
        case .cancelled:
            return "Erkennung wurde abgebrochen"
        case .unknown(let message):
            return "Unbekannter Fehler: \(message)"
        }
    }
}

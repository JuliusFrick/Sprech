// AppState.swift
// Global Observable State for Sprech

import SwiftUI
import Combine
import ApplicationServices

@MainActor
final class AppState: ObservableObject {
    // MARK: - Recording State
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Transcription
    @Published var transcribedText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    
    // MARK: - Settings
    @AppStorage("selectedLanguage") var selectedLanguage: String = "de-DE"
    @AppStorage("translateToLanguage") var translateToLanguage: String = "de-DE"
    @AppStorage("autoClipboard") var autoClipboard: Bool = true
    @AppStorage("playSound") var playSound: Bool = true
    @AppStorage("hotkeyEnabled") var hotkeyEnabled: Bool = true
    
    // MARK: - UI State
    @Published var showSettings: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Services
    private let translationService = TranslationService.shared
    
    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    
    init() {
        setupNotifications()
    }
    
    // MARK: - Setup
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .toggleRecording)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleRecording()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Recording Controls
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingDuration = 0
        errorMessage = nil
        
        // Start duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }
        
        // Play start sound
        if playSound {
            NSSound.beep()
        }
        
        // Actual recording will be handled by AudioEngine
        NotificationCenter.default.post(name: .startAudioCapture, object: nil)
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Play stop sound
        if playSound {
            NSSound.beep()
        }
        
        // Trigger transcription
        isTranscribing = true
        NotificationCenter.default.post(name: .stopAudioCapture, object: nil)
    }
    
    // MARK: - Transcription Handling
    func handleTranscription(_ text: String, detectedLanguage: String? = nil) async {
        var finalText = text
        var wasTranslated = false
        
        // Automatische Übersetzung wenn nötig
        let detected = detectedLanguage ?? detectLanguage(text)
        let targetLangCode = String(translateToLanguage.prefix(2)) // "de-DE" -> "de"
        let detectedLangCode = String(detected.prefix(2))
        
        if detectedLangCode != targetLangCode {
            // Sprache unterscheidet sich - übersetzen!
            do {
                let targetLanguage = languageFromCode(translateToLanguage)
                let result = try await translationService.translate(text, to: targetLanguage)
                finalText = result.translatedText
                wasTranslated = true
            } catch {
                // Übersetzung fehlgeschlagen, Original-Text verwenden
                print("Translation failed: \(error)")
            }
        }
        
        transcribedText = finalText
        isTranscribing = false
        
        // Add to history
        let entry = TranscriptionEntry(
            text: finalText,
            originalText: wasTranslated ? text : nil,
            language: translateToLanguage,
            detectedLanguage: detected,
            duration: recordingDuration,
            wasTranslated: wasTranslated
        )
        transcriptionHistory.insert(entry, at: 0)
        
        // Keep only last 50 entries
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
        
        // Auto-copy/insert
        if autoClipboard {
            insertOrCopyText(finalText)
        }
    }
    
    func handleError(_ message: String) {
        errorMessage = message
        isRecording = false
        isTranscribing = false
    }
    
    // MARK: - Language Detection (simple heuristic)
    private func detectLanguage(_ text: String) -> String {
        // Nutze NSLinguisticTagger für Spracherkennung
        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = text
        
        if let language = tagger.dominantLanguage {
            switch language {
            case "de": return "de-DE"
            case "en": return "en-US"
            case "fr": return "fr-FR"
            case "es": return "es-ES"
            case "it": return "it-IT"
            default: return "de-DE"
            }
        }
        return "de-DE"
    }
    
    private func languageFromCode(_ code: String) -> Language {
        switch code {
        case "de-DE": return .german
        case "en-US": return .english
        case "fr-FR": return .french
        case "es-ES": return .spanish
        case "it-IT": return .italian
        default: return .german
        }
    }
    
    // MARK: - Clipboard & Text Insertion
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Prüft ob ein Textfeld fokussiert ist und fügt Text ein oder kopiert
    func insertOrCopyText(_ text: String) {
        copyToClipboard(text)
        
        let wasFocused = isTextFieldFocused()
        
        if wasFocused {
            // Kleiner Delay, dann Cmd+V simulieren
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePaste()
            }
        }
        
        // Feedback mit Info ob eingefügt oder nur kopiert
        NotificationCenter.default.post(
            name: .textInserted, 
            object: nil,
            userInfo: ["inserted": wasFocused]
        )
    }
    
    func isTextFieldFocused() -> Bool {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            return false
        }
        
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        
        if let roleString = role as? String {
            return roleString == kAXTextFieldRole as String || 
                   roleString == kAXTextAreaRole as String ||
                   roleString == "AXWebArea" ||
                   roleString == "AXComboBox" ||
                   roleString == "AXSearchField"
        }
        
        return false
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // V key = 0x09
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - History Management
    func clearHistory() {
        transcriptionHistory.removeAll()
    }
    
    func deleteEntry(_ entry: TranscriptionEntry) {
        transcriptionHistory.removeAll { $0.id == entry.id }
    }
}

// MARK: - Supporting Types
struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let originalText: String?  // Falls übersetzt
    let language: String
    let detectedLanguage: String
    let duration: TimeInterval
    let timestamp: Date
    let wasTranslated: Bool
    
    init(text: String, originalText: String? = nil, language: String, detectedLanguage: String, duration: TimeInterval, wasTranslated: Bool = false) {
        self.id = UUID()
        self.text = text
        self.originalText = originalText
        self.language = language
        self.detectedLanguage = detectedLanguage
        self.duration = duration
        self.timestamp = Date()
        self.wasTranslated = wasTranslated
    }
}

// MARK: - Additional Notifications
extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let startAudioCapture = Notification.Name("startAudioCapture")
    static let stopAudioCapture = Notification.Name("stopAudioCapture")
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
}

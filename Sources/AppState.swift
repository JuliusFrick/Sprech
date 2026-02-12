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
    @AppStorage("autoClipboard") var autoClipboard: Bool = true
    @AppStorage("playSound") var playSound: Bool = true
    @AppStorage("hotkeyEnabled") var hotkeyEnabled: Bool = true
    
    // MARK: - UI State
    @Published var showSettings: Bool = false
    @Published var errorMessage: String?
    
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
        
        // Actual recording will be handled by AudioEngine (separate module)
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
    func handleTranscription(_ text: String) {
        transcribedText = text
        isTranscribing = false
        
        // Add to history
        let entry = TranscriptionEntry(
            text: text,
            language: selectedLanguage,
            duration: recordingDuration
        )
        transcriptionHistory.insert(entry, at: 0)
        
        // Keep only last 50 entries
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
        
        // Auto-copy/insert
        if autoClipboard {
            insertOrCopyText(text)
        }
    }
    
    func handleError(_ message: String) {
        errorMessage = message
        isRecording = false
        isTranscribing = false
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
        
        if isTextFieldFocused() {
            // Kleiner Delay, dann Cmd+V simulieren
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePaste()
            }
        }
        // Visuelles Feedback wird vom MenuBarView gehandelt
        NotificationCenter.default.post(name: .textInserted, object: nil)
    }
    
    private func isTextFieldFocused() -> Bool {
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
                   roleString == "AXComboBox"
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
    let language: String
    let duration: TimeInterval
    let timestamp: Date
    
    init(text: String, language: String, duration: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.language = language
        self.duration = duration
        self.timestamp = Date()
    }
}

// MARK: - Additional Notifications
extension Notification.Name {
    static let startAudioCapture = Notification.Name("startAudioCapture")
    static let stopAudioCapture = Notification.Name("stopAudioCapture")
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
    static let textInserted = Notification.Name("textInserted")
}

// TextInsertionService.swift
// Sprech - Mac Dictation App
// Intelligenter Text-Einfüge-Service mit Accessibility-Support

import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Types

/// Ergebnis einer Text-Einfüge-Operation
public enum InsertionResult: Sendable {
    /// Text wurde direkt ins Textfeld eingefügt
    case inserted
    /// Text wurde in die Zwischenablage kopiert (kein Textfeld fokussiert)
    case copiedToClipboard
    /// Text wurde via Cmd+V eingefügt
    case pastedViaKeyboard
}

/// Fehler bei der Text-Einfügung
public enum TextInsertionError: Error, LocalizedError, Sendable {
    case noTextFieldFocused
    case accessibilityNotGranted
    case insertionFailed(String)
    case keyboardSimulationFailed
    
    public var errorDescription: String? {
        switch self {
        case .noTextFieldFocused:
            return "Kein Textfeld fokussiert - Text wurde in die Zwischenablage kopiert"
        case .accessibilityNotGranted:
            return "Accessibility-Berechtigung nicht erteilt"
        case .insertionFailed(let reason):
            return "Text konnte nicht eingefügt werden: \(reason)"
        case .keyboardSimulationFailed:
            return "Tastatur-Simulation fehlgeschlagen"
        }
    }
}

// MARK: - TextInsertionService

/// Service für intelligentes Einfügen von Text
/// Prüft ob ein Textfeld fokussiert ist und fügt Text entsprechend ein
@MainActor
public final class TextInsertionService: Sendable {
    
    // MARK: - Singleton
    
    public static let shared = TextInsertionService()
    
    // MARK: - Properties
    
    /// Bevorzugte Einfüge-Methode
    public enum InsertionMethod: Sendable {
        /// Direkt via Accessibility API (setValue)
        case accessibility
        /// Via Cmd+V nach Clipboard-Copy
        case pasteCommand
        /// Versucht Accessibility, dann Fallback zu Paste
        case auto
    }
    
    private var preferredMethod: InsertionMethod = .auto
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Setzt die bevorzugte Einfüge-Methode
    public func setPreferredMethod(_ method: InsertionMethod) {
        preferredMethod = method
    }
    
    // MARK: - Public API
    
    /// Fügt Text intelligent ein
    /// - Parameter text: Der einzufügende Text
    /// - Returns: Das Ergebnis der Einfüge-Operation
    /// - Throws: TextInsertionError wenn Einfügen komplett fehlschlägt
    @discardableResult
    public func insertText(_ text: String) async throws -> InsertionResult {
        guard !text.isEmpty else { return .inserted }
        
        // Prüfe Accessibility-Berechtigung
        guard isAccessibilityEnabled() else {
            copyToClipboard(text)
            throw TextInsertionError.accessibilityNotGranted
        }
        
        // Prüfe ob Textfeld fokussiert
        guard let focusedElement = getFocusedTextElement() else {
            copyToClipboard(text)
            throw TextInsertionError.noTextFieldFocused
        }
        
        // Versuche Text einzufügen basierend auf Methode
        switch preferredMethod {
        case .accessibility:
            return try await insertViaAccessibility(text, element: focusedElement)
            
        case .pasteCommand:
            return try await insertViaPasteCommand(text)
            
        case .auto:
            // Versuche erst Accessibility, dann Paste
            do {
                return try await insertViaAccessibility(text, element: focusedElement)
            } catch {
                return try await insertViaPasteCommand(text)
            }
        }
    }
    
    /// Prüft ob ein Textfeld fokussiert ist
    public func isTextFieldFocused() -> Bool {
        return getFocusedTextElement() != nil
    }
    
    /// Kopiert Text in die Zwischenablage
    public func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    /// Prüft ob Accessibility-Berechtigung erteilt ist
    public func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Fordert Accessibility-Berechtigung an (öffnet System-Dialog)
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Private Methods
    
    /// Holt das fokussierte Textfeld (falls vorhanden)
    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // Prüfe ob es ein text-editierbares Element ist
        if isTextEditable(axElement) {
            return axElement
        }
        
        return nil
    }
    
    /// Prüft ob ein Element Text-editierbar ist
    private func isTextEditable(_ element: AXUIElement) -> Bool {
        // Prüfe Rolle
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        
        if roleResult == .success, let role = roleRef as? String {
            let textRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField"
            ]
            
            if textRoles.contains(role) {
                return true
            }
        }
        
        // Prüfe ob Element beschreibbar ist (hat value und ist nicht read-only)
        var settableRef: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settableRef
        )
        
        if settableResult == .success && settableRef.boolValue {
            return true
        }
        
        // Prüfe subrole für WebAreas etc.
        var subroleRef: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleRef
        )
        
        if subroleResult == .success, let subrole = subroleRef as? String {
            let textSubroles: Set<String> = [
                "AXSearchTextField",
                "AXSecureTextField"
            ]
            
            if textSubroles.contains(subrole) {
                return true
            }
        }
        
        return false
    }
    
    /// Fügt Text via Accessibility API ein
    private func insertViaAccessibility(_ text: String, element: AXUIElement) async throws -> InsertionResult {
        // Hole aktuellen Text und Cursor-Position
        var currentValueRef: CFTypeRef?
        var selectedRangeRef: CFTypeRef?
        
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValueRef)
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef)
        
        let currentValue = (currentValueRef as? String) ?? ""
        
        // Berechne neuen Text
        let newValue: String
        if let rangeValue = selectedRangeRef {
            // Ersetze ausgewählten Text
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                let startIndex = currentValue.index(currentValue.startIndex, offsetBy: range.location, limitedBy: currentValue.endIndex) ?? currentValue.endIndex
                let endIndex = currentValue.index(startIndex, offsetBy: range.length, limitedBy: currentValue.endIndex) ?? currentValue.endIndex
                var mutableValue = currentValue
                mutableValue.replaceSubrange(startIndex..<endIndex, with: text)
                newValue = mutableValue
            } else {
                newValue = currentValue + text
            }
        } else {
            // Append am Ende
            newValue = currentValue + text
        }
        
        // Setze neuen Wert
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFString
        )
        
        guard setResult == .success else {
            throw TextInsertionError.insertionFailed("AXError: \(setResult.rawValue)")
        }
        
        // Setze Cursor ans Ende des eingefügten Texts
        let newCursorPosition: Int
        if let selRange = selectedRangeRef {
            var cfRange = CFRange()
            if AXValueGetValue(selRange as! AXValue, .cfRange, &cfRange) {
                newCursorPosition = cfRange.location + text.count
            } else {
                newCursorPosition = newValue.count
            }
        } else {
            newCursorPosition = newValue.count
        }
        
        var cursorRange = CFRangeMake(newCursorPosition, 0)
        if let rangeValue = AXValueCreate(.cfRange, &cursorRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        
        return .inserted
    }
    
    /// Fügt Text via Cmd+V ein
    private func insertViaPasteCommand(_ text: String) async throws -> InsertionResult {
        // Speichere aktuellen Clipboard-Inhalt
        let previousContent = NSPasteboard.general.string(forType: .string)
        
        // Kopiere neuen Text
        copyToClipboard(text)
        
        // Kleine Verzögerung für Clipboard-Sync
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Simuliere Cmd+V
        let success = simulatePasteCommand()
        
        // Warte kurz, dann stelle alten Clipboard-Inhalt wieder her (optional)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Optionally restore previous clipboard content
        // (Auskommentiert - könnte unerwünschtes Verhalten verursachen)
        // if let previous = previousContent {
        //     copyToClipboard(previous)
        // }
        
        guard success else {
            throw TextInsertionError.keyboardSimulationFailed
        }
        
        return .pastedViaKeyboard
    }
    
    /// Simuliert Cmd+V Tastenkombination
    private func simulatePasteCommand() -> Bool {
        // Cmd Down
        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true) else {
            return false
        }
        cmdDown.flags = .maskCommand
        
        // V Down
        guard let vDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            return false
        }
        vDown.flags = .maskCommand
        
        // V Up
        guard let vUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }
        vUp.flags = .maskCommand
        
        // Cmd Up
        guard let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            return false
        }
        
        // Post events
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        
        return true
    }
}

// MARK: - Convenience Extension

extension TextInsertionService {
    
    /// Fügt Text ein und gibt Feedback-String zurück
    public func insertTextWithFeedback(_ text: String) async -> (success: Bool, message: String) {
        do {
            let result = try await insertText(text)
            switch result {
            case .inserted:
                return (true, "Eingefügt ✓")
            case .pastedViaKeyboard:
                return (true, "Eingefügt ✓")
            case .copiedToClipboard:
                return (true, "📋 Kopiert")
            }
        } catch let error as TextInsertionError {
            switch error {
            case .noTextFieldFocused:
                return (false, "📋 Kopiert (kein Textfeld)")
            case .accessibilityNotGranted:
                return (false, "⚠️ Accessibility-Berechtigung fehlt")
            case .insertionFailed:
                return (false, "⚠️ Einfügen fehlgeschlagen")
            case .keyboardSimulationFailed:
                return (false, "⚠️ Tastatur-Simulation fehlgeschlagen")
            }
        } catch {
            return (false, "⚠️ Unbekannter Fehler")
        }
    }
}

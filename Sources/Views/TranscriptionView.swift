// TranscriptionView.swift
// Displays transcribed text with actions

import SwiftUI

struct TranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label
            HStack {
                Image(systemName: "text.quote")
                    .foregroundStyle(.secondary)
                Text("Transkription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Copy button
                Button(action: copyText) {
                    Label(isCopied ? "Kopiert!" : "Kopieren", 
                          systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(isCopied ? .green : .accent)
            }
            
            // Text content
            Text(appState.transcribedText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Actions
            HStack(spacing: 12) {
                Button(action: insertAtCursor) {
                    Label("Einfügen", systemImage: "text.insert")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                
                Button(action: { appState.transcribedText = "" }) {
                    Label("Verwerfen", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Spacer()
            }
        }
        .padding()
    }
    
    private func copyText() {
        appState.copyToClipboard(appState.transcribedText)
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func insertAtCursor() {
        // Copy and simulate paste via accessibility
        appState.copyToClipboard(appState.transcribedText)
        
        // Simulate Cmd+V using CGEvent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulatePaste()
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Key down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        
        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - History View (for Settings)
struct TranscriptionHistoryView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Verlauf")
                    .font(.headline)
                
                Spacer()
                
                if !appState.transcriptionHistory.isEmpty {
                    Button("Alle löschen") {
                        appState.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            
            if appState.transcriptionHistory.isEmpty {
                ContentUnavailableView(
                    "Noch keine Transkriptionen",
                    systemImage: "text.quote",
                    description: Text("Deine Transkriptionen erscheinen hier")
                )
                .frame(height: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.transcriptionHistory) { entry in
                            HistoryEntryRow(entry: entry)
                                .environmentObject(appState)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptionEntry
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.callout)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .relative)
                    Text("•")
                    Text(formatDuration(entry.duration))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: { appState.copyToClipboard(entry.text) }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { appState.deleteEntry(entry) }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }
}

#Preview {
    TranscriptionView()
        .environmentObject({
            let state = AppState()
            state.transcribedText = "Das ist ein Beispieltext der transkribiert wurde."
            return state
        }())
        .frame(width: 320)
}

// MenuBarView.swift
// Main Menubar Popup UI

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var isHoveringRecord = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Main Content
            if appState.isRecording {
                recordingView
            } else if appState.isTranscribing {
                transcribingView
            } else {
                idleView
            }
            
            // Transcription Result
            if !appState.transcribedText.isEmpty && !appState.isRecording {
                Divider()
                TranscriptionView()
                    .environmentObject(appState)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.accent)
            
            Text("Sprech")
                .font(.headline)
            
            Spacer()
            
            // Language badge
            Text(languageFlag)
                .font(.title3)
                .help("Sprache: \(appState.selectedLanguage)")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    // MARK: - Recording View
    private var recordingView: some View {
        VStack(spacing: 16) {
            // Animated waveform
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    WaveformBar(index: index)
                }
            }
            .frame(height: 40)
            
            // Duration
            Text(formatDuration(appState.recordingDuration))
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.secondary)
            
            // Stop button
            Button(action: appState.stopRecording) {
                Label("Aufnahme stoppen", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            
            Text("⌘⇧D zum Stoppen")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
    
    // MARK: - Transcribing View
    private var transcribingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            
            Text("Wird transkribiert...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
    }
    
    // MARK: - Idle View
    private var idleView: some View {
        VStack(spacing: 16) {
            // Record button
            Button(action: appState.startRecording) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                    Text("Diktieren")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .scaleEffect(isHoveringRecord ? 1.02 : 1.0)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringRecord = hovering
                }
            }
            
            // Hotkey hint
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                Text("⌘⇧D")
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(.tertiary)
            
            // Error message
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    // MARK: - Footer
    private var footer: some View {
        HStack {
            Button(action: { appState.showSettings = true }) {
                Label("Einstellungen", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(action: { NSApp.terminate(nil) }) {
                Label("Beenden", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    private var languageFlag: String {
        switch appState.selectedLanguage {
        case "de-DE": return "🇩🇪"
        case "en-US": return "🇺🇸"
        case "en-GB": return "🇬🇧"
        case "fr-FR": return "🇫🇷"
        case "es-ES": return "🇪🇸"
        case "it-IT": return "🇮🇹"
        default: return "🌐"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Waveform Bar Animation
struct WaveformBar: View {
    let index: Int
    @State private var height: CGFloat = 10
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.accent)
            .frame(width: 4, height: height)
            .onAppear {
                animate()
            }
    }
    
    private func animate() {
        let delay = Double(index) * 0.1
        withAnimation(
            .easeInOut(duration: 0.4)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            height = CGFloat.random(in: 15...40)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}

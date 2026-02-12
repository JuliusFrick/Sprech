// MenuBarView.swift
// Minimales Menubar-only UI für Sprech

import SwiftUI
import ServiceManagement

// MARK: - Main View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioManager = AudioSessionManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    // Text insertion handled by AppState
    
    @State private var feedbackMessage: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var showNoTextFieldWarning = false
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("selectedModelSpeed") private var selectedModelSpeed = "balanced"
    @AppStorage("translateToLanguage") private var translateToLanguage = "de-DE"
    
    private var isActive: Bool {
        appState.isRecording || appState.isTranscribing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Waveform + Text (kompakt)
            contentArea
            
            // Divider nur wenn Settings sichtbar
            if !isActive {
                Divider()
                    .padding(.horizontal, 12)
            }
            
            // Settings oder Footer
            if isActive {
                compactFooter
            } else {
                settingsArea
                footerArea
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(NotificationCenter.default.publisher(for: .textInserted)) { notification in
            handleTextInserted(notification)
        }
        .onAppear {
            checkTextFieldStatus()
        }
    }
    
    // MARK: - Content Area (Waveform + Text)
    
    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 6) {
            if isActive {
                // Recording: Waveform + Live Text
                HStack(spacing: 8) {
                    // Mini Waveform
                    MiniWaveform(audioLevel: audioManager.inputLevel)
                        .frame(width: 60, height: 24)
                    
                    // Pulsing dot
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .modifier(PulseModifier())
                    
                    Spacer()
                    
                    // Duration
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Scrolling text with gradient fade
                ScrollingTextView(text: transcriptionManager.currentTranscription.text)
                    .frame(height: 28)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
            } else if let message = feedbackMessage {
                // Feedback: "Eingefügt ✓" oder "📋 Kopiert"
                HStack(spacing: 8) {
                    Image(systemName: message.contains("Eingefügt") ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                        .foregroundStyle(message.contains("Eingefügt") ? .green : .blue)
                    Text(message)
                        .font(.callout)
                }
                .padding(.vertical, 16)
                
            } else {
                // Idle: Mic + Hint
                VStack(spacing: 6) {
                    PulsingMicCircle(isActive: false)
                        .frame(width: 32, height: 32)
                    
                    Text("⌘⇧D")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    // Warning wenn kein Textfeld
                    if showNoTextFieldWarning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Kein Textfeld ausgewählt")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
    
    // MARK: - Compact Footer (during recording)
    
    private var compactFooter: some View {
        HStack {
            // Stop button
            Button(action: { 
                appState.stopRecording()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                    Text("Stopp")
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            // Current language indicator
            Text(languageFlag(translateToLanguage))
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Settings Area (Inline)
    
    private var settingsArea: some View {
        HStack(spacing: 12) {
            // Output Language (was du haben willst)
            HStack(spacing: 4) {
                Text("→")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                Picker("", selection: $translateToLanguage) {
                    Text("🇩🇪").tag("de-DE")
                    Text("🇺🇸").tag("en-US")
                    Text("🇫🇷").tag("fr-FR")
                    Text("🇪🇸").tag("es-ES")
                    Text("🇮🇹").tag("it-IT")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 50)
            }
            .help("Ausgabe-Sprache (übersetzt automatisch)")
            
            Divider()
                .frame(height: 16)
            
            // Model Speed
            Picker("", selection: $selectedModelSpeed) {
                Text("⚡").tag("fast")
                Text("⚖️").tag("balanced")
                Text("🎯").tag("precise")
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .help("Schnell / Ausgewogen / Präzise")
            .onChange(of: selectedModelSpeed) { _, newValue in
                updateModelForSpeed(newValue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Footer
    
    private var footerArea: some View {
        HStack {
            // Settings Gear
            Menu {
                Toggle("Beim Start öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                
                Divider()
                
                Button("Beenden") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            
            Spacer()
            
            Text("Sprech")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            
            Spacer()
            
            // Refresh text field status
            Button(action: checkTextFieldStatus) {
                Image(systemName: showNoTextFieldWarning ? "text.cursor" : "checkmark.circle")
                    .foregroundStyle(showNoTextFieldWarning ? .orange : .green)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Textfeld-Status prüfen")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d.%d", seconds, tenths)
    }
    
    private func languageFlag(_ code: String) -> String {
        switch code {
        case "de-DE": return "🇩🇪"
        case "en-US": return "🇺🇸"
        case "fr-FR": return "🇫🇷"
        case "es-ES": return "🇪🇸"
        case "it-IT": return "🇮🇹"
        default: return "🌐"
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
    
    private func updateModelForSpeed(_ speed: String) {
        let providerId: String
        switch speed {
        case "fast": providerId = "whisper-tiny"
        case "balanced": providerId = "whisper-small"
        case "precise": providerId = "whisper-medium"
        default: providerId = "whisper-small"
        }
        
        Task {
            await transcriptionManager.switchProvider(toId: providerId)
        }
    }
    
    private func checkTextFieldStatus() {
        showNoTextFieldWarning = !appState.isTextFieldFocused()
    }
    
    private func handleTextInserted(_ notification: Notification) {
        let wasInserted = notification.userInfo?["inserted"] as? Bool ?? false
        
        feedbackTask?.cancel()
        
        withAnimation(.easeInOut(duration: 0.15)) {
            feedbackMessage = wasInserted ? "Eingefügt ✓" : "📋 Kopiert"
        }
        
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        feedbackMessage = nil
                    }
                }
            }
        }
    }
}

// MARK: - Scrolling Text View (Gradient Fade Left)

struct ScrollingTextView: View {
    let text: String
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Gradient fade on left
                LinearGradient(
                    colors: [.clear, .clear.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
                .blendMode(.destinationOut)
                
                // Text aligned right, scrolls left
                Text(text.isEmpty ? "..." : text)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .compositingGroup()
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 30)
                    
                    Rectangle()
                        .fill(.white)
                }
            )
        }
    }
}

// MARK: - Mini Waveform

struct MiniWaveform: View {
    let audioLevel: Float
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { index in
                MiniBar(index: index, level: CGFloat(audioLevel))
            }
        }
    }
}

struct MiniBar: View {
    let index: Int
    let level: CGFloat
    
    @State private var height: CGFloat = 4
    
    private var multiplier: CGFloat {
        // Center bars taller
        let distance = abs(index - 4)
        return 1.0 - (CGFloat(distance) * 0.15)
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 3, height: height)
            .onChange(of: level) { _, newLevel in
                let base: CGFloat = 4
                let maxAdd: CGFloat = 16
                let variance = CGFloat.random(in: 0.7...1.3)
                
                withAnimation(.easeOut(duration: 0.08)) {
                    height = base + (maxAdd * newLevel * multiplier * variance)
                }
            }
    }
}

// MARK: - Pulsing Mic Circle

struct PulsingMicCircle: View {
    let isActive: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.red : Color.secondary.opacity(0.15))
            
            Image(systemName: isActive ? "mic.fill" : "mic")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? .white : .secondary)
        }
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let textInserted = Notification.Name("textInserted")
}

// MARK: - Preview

#Preview("Idle") {
    MenuBarView()
        .environmentObject(AppState())
}

#Preview("Recording") {
    MenuBarView()
        .environmentObject({
            let state = AppState()
            state.isRecording = true
            state.recordingDuration = 3.7
            return state
        }())
}

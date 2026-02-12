// MenuBarView.swift
// Minimales Menubar-only UI für Sprech
// Inspiriert von Apple Dictation, CleanShot X, Raycast

import SwiftUI
import ServiceManagement

// MARK: - Main View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioManager = AudioSessionManager.shared
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    
    @State private var showCopiedFeedback = false
    @State private var copiedFeedbackTask: Task<Void, Never>?
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("selectedModelSpeed") private var selectedModelSpeed = "balanced"
    
    private var currentState: ViewState {
        if showCopiedFeedback { return .done }
        if appState.isTranscribing { return .processing }
        if appState.isRecording { return .recording }
        return .idle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Waveform / Status
            statusArea
            
            // Middle: Live Text
            if currentState == .recording || currentState == .processing || currentState == .done {
                textArea
            }
            
            Divider()
                .padding(.horizontal, 12)
            
            // Bottom: Settings (nur im Idle)
            if currentState == .idle {
                settingsArea
            }
            
            // Footer
            footerArea
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(NotificationCenter.default.publisher(for: .textInserted)) { _ in
            showCopiedFeedbackAnimation()
        }
    }
    
    // MARK: - Status Area
    
    @ViewBuilder
    private var statusArea: some View {
        VStack(spacing: 8) {
            switch currentState {
            case .idle:
                idleIndicator
                
            case .recording:
                WaveformView(audioLevel: audioManager.inputLevel)
                    .frame(height: 50)
                
            case .processing:
                processingIndicator
                
            case .done:
                doneIndicator
            }
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    private var idleIndicator: some View {
        VStack(spacing: 6) {
            PulsingMicCircle(isActive: false)
            
            Text("⌘⇧D zum Starten")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var processingIndicator: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Verarbeite...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var doneIndicator: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            
            Text("📋 Kopiert!")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Text Area
    
    @ViewBuilder
    private var textArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isRecording {
                // Live transcription während Recording
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(pulsingOpacity)
                    
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                if !transcriptionManager.currentTranscription.text.isEmpty {
                    Text(transcriptionManager.currentTranscription.text)
                        .font(.callout)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !appState.transcribedText.isEmpty {
                // Final text
                Text(appState.transcribedText)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }
    
    @State private var pulsingOpacity: Double = 1.0
    
    // MARK: - Settings Area (Inline)
    
    private var settingsArea: some View {
        VStack(spacing: 10) {
            // Language Picker
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Picker("", selection: $appState.selectedLanguage) {
                    Text("🇩🇪 Deutsch").tag("de-DE")
                    Text("🇺🇸 English").tag("en-US")
                    Text("🇫🇷 Français").tag("fr-FR")
                    Text("🇪🇸 Español").tag("es-ES")
                    Text("🇮🇹 Italiano").tag("it-IT")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Model Speed Picker
            HStack {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Picker("", selection: $selectedModelSpeed) {
                    Text("⚡ Schnell").tag("fast")
                    Text("⚖️ Ausgewogen").tag("balanced")
                    Text("🎯 Präzise").tag("precise")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedModelSpeed) { _, newValue in
                    updateModelForSpeed(newValue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Footer
    
    private var footerArea: some View {
        HStack {
            // Settings Gear für Launch at Login
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
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            
            Spacer()
            
            // Error display
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Recording button / Stop button
            if appState.isRecording {
                Button(action: appState.stopRecording) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    
// MARK: - Feedback Animation
    
    private func showCopiedFeedbackAnimation() {
        copiedFeedbackTask?.cancel()
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }
        
        copiedFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showCopiedFeedback = false
                    }
                }
            }
        }
    }
}

// MARK: - View State

private enum ViewState {
    case idle
    case recording
    case processing
    case done
}

// MARK: - Waveform View

struct WaveformView: View {
    let audioLevel: Float
    
    @State private var barHeights: [CGFloat] = Array(repeating: 4, count: 7)
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                WaveformBar(height: barHeights[index])
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(for: newLevel)
        }
        .onAppear {
            // Initial animation
            animateBars()
        }
    }
    
    private func updateBars(for level: Float) {
        let normalizedLevel = CGFloat(min(max(level, 0), 1))
        let baseHeight: CGFloat = 4
        let maxAdditional: CGFloat = 36
        
        withAnimation(.easeOut(duration: 0.08)) {
            for i in 0..<7 {
                // Verschiedene Multiplikatoren für natürlichere Bewegung
                let multiplier: CGFloat
                switch i {
                case 3: multiplier = 1.0      // Center highest
                case 2, 4: multiplier = 0.85
                case 1, 5: multiplier = 0.6
                default: multiplier = 0.4
                }
                
                let randomVariance = CGFloat.random(in: 0.8...1.2)
                barHeights[i] = baseHeight + (maxAdditional * normalizedLevel * multiplier * randomVariance)
            }
        }
    }
    
    private func animateBars() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if audioLevel < 0.01 {
                // Idle animation when no audio
                withAnimation(.easeInOut(duration: 0.3)) {
                    for i in 0..<7 {
                        barHeights[i] = CGFloat.random(in: 4...12)
                    }
                }
            }
        }
    }
}

struct WaveformBar: View {
    let height: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.7)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: height)
    }
}

// MARK: - Pulsing Mic Circle

struct PulsingMicCircle: View {
    let isActive: Bool
    
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Outer pulse ring (when active)
            if isActive {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            }
            
            // Main circle
            Circle()
                .fill(isActive ? Color.red : Color.secondary.opacity(0.2))
                .frame(width: 36, height: 36)
            
            // Mic icon
            Image(systemName: isActive ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? .white : .secondary)
        }
        .onAppear {
            if isActive {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Idle") {
    MenuBarView()
        .environmentObject(AppState())
        .frame(width: 300, height: 200)
}

#Preview("Recording") {
    MenuBarView()
        .environmentObject({
            let state = AppState()
            state.isRecording = true
            state.recordingDuration = 5.3
            return state
        }())
        .frame(width: 300, height: 200)
}

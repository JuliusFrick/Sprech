// SettingsView.swift
// App Settings UI - Menschlich & Verständlich

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Allgemein", systemImage: "gear")
                }
            
            SpeechSettingsView()
                .environmentObject(appState)
                .environmentObject(transcriptionManager)
                .tabItem {
                    Label("Sprache", systemImage: "waveform")
                }
            
            HotkeySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Steuerung", systemImage: "keyboard")
                }
            
            TranscriptionHistoryView()
                .environmentObject(appState)
                .tabItem {
                    Label("Verlauf", systemImage: "clock")
                }
            
            AboutView()
                .tabItem {
                    Label("Info", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Sprech beim Mac-Start öffnen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Automatisch starten")
            }
            
            Section {
                Toggle("Sound abspielen", isOn: $appState.playSound)
                Text("Kurzer Ton wenn Aufnahme startet oder stoppt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Feedback")
            }
            
            Section {
                Toggle("Text automatisch kopieren", isOn: $appState.autoClipboard)
                Text("Nach dem Diktieren landet der Text direkt in deiner Zwischenablage — bereit zum Einfügen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Nach dem Sprechen")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
}

// MARK: - Speech Settings (Combined Language + Model Selection)
struct SpeechSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @State private var downloadProgress: [String: Double] = [:]
    @State private var isDownloading: [String: Bool] = [:]
    
    let languages = [
        ("de-DE", "🇩🇪 Deutsch"),
        ("en-US", "🇺🇸 Englisch"),
        ("fr-FR", "🇫🇷 Französisch"),
        ("es-ES", "🇪🇸 Spanisch"),
        ("it-IT", "🇮🇹 Italienisch"),
    ]
    
    var body: some View {
        Form {
            Section {
                Picker("Ich spreche", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            } header: {
                Text("Deine Sprache")
            }
            
            Section {
                ForEach(transcriptionManager.availableProviders, id: \.id) { provider in
                    ModelRowView(
                        provider: provider,
                        isSelected: transcriptionManager.selectedProvider?.id == provider.id,
                        downloadProgress: downloadProgress[provider.id] ?? 0,
                        isDownloading: isDownloading[provider.id] ?? false,
                        onSelect: {
                            Task { await transcriptionManager.switchProvider(to: provider) }
                        },
                        onDownload: {
                            Task { await downloadModel(provider) }
                        },
                        onDelete: {
                            Task { try? await transcriptionManager.deleteModels(for: provider.id) }
                        }
                    )
                }
            } header: {
                Text("Wie soll ich dich verstehen?")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Alles bleibt auf deinem Mac", systemImage: "lock.shield.fill")
                    Text("Deine Stimme wird nie ins Internet geschickt.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .task {
            await transcriptionManager.refreshProviderStatus()
        }
    }
    
    private func downloadModel(_ provider: any TranscriptionProvider) async {
        isDownloading[provider.id] = true
        try? await transcriptionManager.downloadModels(for: provider.id) { progress in
            Task { @MainActor in
                downloadProgress[provider.id] = progress
            }
        }
        isDownloading[provider.id] = false
    }
}

// MARK: - Model Row (Human-Friendly)
struct ModelRowView: View {
    let provider: any TranscriptionProvider
    let isSelected: Bool
    let downloadProgress: Double
    let isDownloading: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @State private var status: ProviderStatus = .unavailable(reason: "")
    
    private var humanName: String {
        switch provider.id {
        case "apple-speech": return "Standard"
        case "whisper-tiny": return "Schnell"
        case "whisper-base": return "Schnell+"
        case "whisper-small": return "Ausgewogen"
        case "whisper-medium": return "Präzise"
        case "whisper-large": return "Maximum"
        case "voxtral": return "Voxtral"
        default: return provider.displayName
        }
    }
    
    private var humanDescription: String {
        switch provider.id {
        case "apple-speech": 
            return "Eingebaut in deinen Mac. Sofort einsatzbereit."
        case "whisper-tiny": 
            return "Blitzschnell, gut für kurze Notizen"
        case "whisper-base": 
            return "Schnell mit besserer Genauigkeit"
        case "whisper-small": 
            return "Gute Balance aus Geschwindigkeit und Qualität"
        case "whisper-medium": 
            return "Sehr genau, ideal für wichtige Texte"
        case "whisper-large": 
            return "Beste Qualität, braucht mehr Zeit"
        case "voxtral": 
            return "Kommt bald — neues Modell von Mistral"
        default: 
            return provider.description
        }
    }
    
    private var icon: String {
        switch provider.id {
        case "apple-speech": return "apple.logo"
        case "voxtral": return "sparkles"
        default: return "brain"
        }
    }
    
    private var isComingSoon: Bool {
        provider.id == "voxtral"
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Selection
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                }
            }
            
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isComingSoon ? .secondary : .primary)
                .frame(width: 28)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(humanName)
                        .font(.headline)
                        .foregroundStyle(isComingSoon ? .secondary : .primary)
                    
                    if isComingSoon {
                        Text("BALD")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    } else if case .ready = status {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                
                Text(humanDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action
            if !isComingSoon {
                actionView
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isComingSoon && status.isAvailable {
                onSelect()
            }
        }
        .opacity(isComingSoon ? 0.6 : 1)
        .task {
            status = await provider.status
        }
    }
    
    @ViewBuilder
    private var actionView: some View {
        if isDownloading {
            VStack(spacing: 2) {
                ProgressView(value: downloadProgress)
                    .frame(width: 50)
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if case .needsDownload = status {
            Button(action: onDownload) {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                    if let size = provider.downloadSize {
                        Text(size)
                            .font(.caption2)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.accent)
        } else if case .ready = status, provider.requiresDownload {
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
    }
}

// MARK: - Hotkey Settings
struct HotkeySettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Zum Diktieren drücke")
                        Spacer()
                        HStack(spacing: 4) {
                            KeyCapView(key: "⌘")
                            KeyCapView(key: "⇧")
                            KeyCapView(key: "D")
                        }
                    }
                    
                    Text("Funktioniert überall — egal welche App gerade offen ist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Tastenkürzel")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TipRow(emoji: "👆", text: "Einmal drücken startet die Aufnahme, nochmal drücken stoppt sie")
                    TipRow(emoji: "✊", text: "Oder: Gedrückt halten während du sprichst, loslassen wenn fertig")
                    TipRow(emoji: "🎯", text: "Der Text wird dort eingefügt, wo dein Cursor gerade ist")
                }
            } header: {
                Text("So funktioniert's")
            }
        }
        .formStyle(.grouped)
    }
}

struct TipRow: View {
    let emoji: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct KeyCapView: View {
    let key: String
    
    var body: some View {
        Text(key)
            .font(.system(.body, design: .rounded, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - History View (simplified)
struct TranscriptionHistoryView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            if appState.transcriptionHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Noch keine Aufnahmen")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Deine diktierten Texte erscheinen hier")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.transcriptionHistory.reversed(), id: \.id) { item in
                        HistoryRowView(item: item)
                    }
                    .onDelete { indexSet in
                        let reversed = Array(appState.transcriptionHistory.reversed())
                        for index in indexSet {
                            if let originalIndex = appState.transcriptionHistory.firstIndex(where: { $0.id == reversed[index].id }) {
                                appState.transcriptionHistory.remove(at: originalIndex)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let item: TranscriptionHistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .lineLimit(2)
            
            Text(item.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.text, forType: .string)
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.accent)
            
            VStack(spacing: 4) {
                Text("Sprech")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Diktieren, einfach gemacht")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                FeatureRow(icon: "waveform", text: "Sprache zu Text")
                FeatureRow(icon: "sparkles", text: "Füllwörter entfernen")
                FeatureRow(icon: "globe", text: "Übersetzen")
                FeatureRow(icon: "lock.shield", text: "100% privat")
            }
            .padding(.vertical)
            
            Spacer()
            
            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }
}

// MARK: - Transcription History Item (if not defined elsewhere)
struct TranscriptionHistoryItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    
    init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

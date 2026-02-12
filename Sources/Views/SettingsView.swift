// SettingsView.swift
// App Settings UI

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
            
            TranscriptionSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Transkription", systemImage: "text.quote")
                }
            
            ModelsSettingsView()
                .environmentObject(transcriptionManager)
                .tabItem {
                    Label("Modelle", systemImage: "cpu")
                }
            
            HotkeySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Tastenkürzel", systemImage: "keyboard")
                }
            
            TranscriptionHistoryView()
                .environmentObject(appState)
                .tabItem {
                    Label("Verlauf", systemImage: "clock")
                }
            
            AboutView()
                .tabItem {
                    Label("Über", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                
                Toggle("Ton bei Start/Stop abspielen", isOn: $appState.playSound)
                
                Toggle("Text automatisch kopieren", isOn: $appState.autoClipboard)
                    .help("Kopiert den transkribierten Text automatisch in die Zwischenablage")
            } header: {
                Text("Verhalten")
            }
            
            Section {
                LabeledContent("Version") {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("Build") {
                    Text("2024.1")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Info")
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

// MARK: - Transcription Settings
struct TranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    let languages = [
        ("de-DE", "🇩🇪 Deutsch"),
        ("en-US", "🇺🇸 Englisch (US)"),
        ("en-GB", "🇬🇧 Englisch (UK)"),
        ("fr-FR", "🇫🇷 Französisch"),
        ("es-ES", "🇪🇸 Spanisch"),
        ("it-IT", "🇮🇹 Italienisch"),
        ("pt-BR", "🇧🇷 Portugiesisch"),
        ("nl-NL", "🇳🇱 Niederländisch"),
        ("pl-PL", "🇵🇱 Polnisch"),
        ("ja-JP", "🇯🇵 Japanisch"),
        ("zh-CN", "🇨🇳 Chinesisch"),
    ]
    
    var body: some View {
        Form {
            Section {
                Picker("Sprache", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .help("Sprache für die Spracherkennung")
            } header: {
                Text("Spracherkennung")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transkriptions-Engine")
                        .font(.headline)
                    
                    Text("Sprech verwendet Apple's eingebaute Spracherkennung für schnelle, lokale Verarbeitung. Deine Aufnahmen verlassen nie dein Gerät.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Datenschutz")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey Settings
struct HotkeySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecordingHotkey = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Globales Tastenkürzel aktivieren", isOn: $appState.hotkeyEnabled)
                
                HStack {
                    Text("Tastenkürzel")
                    Spacer()
                    
                    HStack(spacing: 4) {
                        KeyCapView(key: "⌘")
                        KeyCapView(key: "⇧")
                        KeyCapView(key: "D")
                    }
                }
                
                Text("Drücke ⌘⇧D um die Aufnahme zu starten/stoppen, egal welche App aktiv ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tastenkürzel")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tipp", systemImage: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    
                    Text("Für beste Ergebnisse:\n• Halte ⌘⇧D gedrückt während du sprichst\n• Oder drücke einmal zum Starten, nochmal zum Stoppen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Hinweise")
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyCapView: View {
    let key: String
    
    var body: some View {
        Text(key)
            .font(.system(.body, design: .rounded, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Models Settings (Provider Selection)
struct ModelsSettingsView: View {
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @State private var downloadProgress: [String: Double] = [:]
    @State private var isDownloading: [String: Bool] = [:]
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                ForEach(transcriptionManager.availableProviders, id: \.id) { provider in
                    ProviderRowView(
                        provider: provider,
                        isSelected: transcriptionManager.selectedProvider?.id == provider.id,
                        downloadProgress: downloadProgress[provider.id] ?? 0,
                        isDownloading: isDownloading[provider.id] ?? false,
                        onSelect: {
                            Task {
                                await transcriptionManager.switchProvider(to: provider)
                            }
                        },
                        onDownload: {
                            Task {
                                await downloadModels(for: provider)
                            }
                        },
                        onDelete: {
                            Task {
                                await deleteModels(for: provider)
                            }
                        }
                    )
                }
            } header: {
                Text("Transcription Engines")
            } footer: {
                Text("Alle Engines funktionieren komplett offline. Keine API-Keys erforderlich.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Toggle("Nur Offline-Modelle verwenden", isOn: Binding(
                    get: { transcriptionManager.currentSettings.preferOfflineOnly },
                    set: { transcriptionManager.setPreferOfflineOnly($0) }
                ))
                .help("Verhindert die Nutzung von Server-basierter Erkennung")
                
                Toggle("Modelle automatisch herunterladen", isOn: .constant(false))
                    .disabled(true)
                    .help("Kommt bald: Automatischer Download von empfohlenen Modellen")
            } header: {
                Text("Einstellungen")
            }
            
            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await transcriptionManager.refreshProviderStatus()
        }
    }
    
    private func downloadModels(for provider: any TranscriptionProvider) async {
        isDownloading[provider.id] = true
        downloadProgress[provider.id] = 0
        errorMessage = nil
        
        do {
            try await transcriptionManager.downloadModels(for: provider.id) { progress in
                Task { @MainActor in
                    downloadProgress[provider.id] = progress
                }
            }
            isDownloading[provider.id] = false
        } catch {
            errorMessage = error.localizedDescription
            isDownloading[provider.id] = false
        }
    }
    
    private func deleteModels(for provider: any TranscriptionProvider) async {
        errorMessage = nil
        
        do {
            try await transcriptionManager.deleteModels(for: provider.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Provider Row
struct ProviderRowView: View {
    let provider: any TranscriptionProvider
    let isSelected: Bool
    let downloadProgress: Double
    let isDownloading: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @State private var status: ProviderStatus = .unavailable(reason: "Laden...")
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .accent : .secondary)
                .font(.title2)
            
            // Provider info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.displayName)
                        .font(.headline)
                    
                    if provider.isOfflineCapable {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .help("Funktioniert offline")
                    }
                }
                
                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                // Status
                HStack(spacing: 4) {
                    statusIcon
                    Text(status.displayText)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }
            
            Spacer()
            
            // Actions
            actionButtons
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if status.isAvailable {
                onSelect()
            }
        }
        .task {
            status = await provider.status
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            ProgressView()
                .scaleEffect(0.6)
        case .needsDownload:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
        case .unavailable:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .ready: return .green
        case .downloading: return .blue
        case .needsDownload: return .blue
        case .unavailable: return .orange
        case .error: return .red
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if isDownloading {
            VStack(spacing: 2) {
                ProgressView(value: downloadProgress)
                    .frame(width: 60)
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if provider.requiresDownload {
            if case .needsDownload = status {
                Button(action: onDownload) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                        if let size = provider.downloadSize {
                            Text(size)
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.accent)
            } else if case .ready = status {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Modell löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.accent)
            
            Text("Sprech")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Diktiersoftware für macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Text("Version 1.0.0")
                Text("© 2024")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            
            Spacer()
            
            HStack(spacing: 20) {
                Link(destination: URL(string: "https://github.com")!) {
                    Label("GitHub", systemImage: "link")
                }
                
                Link(destination: URL(string: "mailto:support@example.com")!) {
                    Label("Support", systemImage: "envelope")
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

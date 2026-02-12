// SettingsView.swift
// App Settings UI

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
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
        .frame(width: 450, height: 350)
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

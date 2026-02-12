// SprechApp.swift
// Sprech - Mac Menubar Dictation App
// Swift 6, macOS 14+

import SwiftUI
import Carbon.HIToolbox

@main
struct SprechApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("Sprech")
            } icon: {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "mic.circle")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate for Global Hotkey & Dock Icon Hiding
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menubar only
        NSApp.setActivationPolicy(.accessory)
        
        // Register global hotkey (Cmd+Shift+D)
        registerGlobalHotkey()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func registerGlobalHotkey() {
        // Global hotkey: Cmd+Shift+D
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let cmdShiftD = event.modifierFlags.contains([.command, .shift]) && event.keyCode == kVK_ANSI_D
            
            if cmdShiftD {
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
            }
        }
        
        // Also monitor local events when app is focused
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let cmdShiftD = event.modifierFlags.contains([.command, .shift]) && event.keyCode == kVK_ANSI_D
            
            if cmdShiftD {
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
                return nil // Consume event
            }
            return event
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
}

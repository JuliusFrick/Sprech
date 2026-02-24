// SprechApp.swift
// Sprech - Mac Menubar Dictation App
// Swift 6, macOS 14+

import SwiftUI
import Carbon.HIToolbox
import AppKit

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
    }
}

// MARK: - App Delegate for Global Hotkey & Dock Icon Hiding
class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalKeyDownMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isFunctionKeyPressed = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menubar only
        NSApp.setActivationPolicy(.accessory)
        
        // Register global input monitoring
        registerGlobalInputMonitors()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        removeMonitors()
        NotchGlowController.shared.setRecordingActive(false)
    }
    
    private func registerGlobalInputMonitors() {
        // Global hotkey: Cmd+Shift+D
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyDown(event)
        }
        
        // Global function key (Fn) hold for push-to-talk
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Also monitor local events when app is focused
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyDown(event) == true {
                return nil // Consume event
            }
            return event
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }
    
    private func removeMonitors() {
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
    }
    
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let cmdShiftD = event.modifierFlags.contains([.command, .shift]) && event.keyCode == kVK_ANSI_D
        
        if cmdShiftD {
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
            return true
        }
        
        return false
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isFnDown = currentFlags.contains(.function)
        
        guard isFnDown != isFunctionKeyPressed else {
            return
        }
        
        isFunctionKeyPressed = isFnDown
        
        if isFnDown {
            NotificationCenter.default.post(name: .functionKeyDown, object: nil)
        } else {
            NotificationCenter.default.post(name: .functionKeyUp, object: nil)
        }
    }
}

@MainActor
final class NotchGlowController {
    static let shared = NotchGlowController()
    
    private var overlayPanel: NSPanel?
    
    private init() {}
    
    func setRecordingActive(_ isActive: Bool) {
        if isActive {
            showIfAvailable()
        } else {
            hide()
        }
    }
    
    private func showIfAvailable() {
        guard let screen = preferredNotchScreen(),
              let notchWidth = notchWidth(on: screen) else {
            hide()
            return
        }
        
        let panelSize = panelSize(for: notchWidth)
        let frame = panelFrame(for: screen, size: panelSize)
        
        let panel = ensurePanel(screen: screen, frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
    
    private func hide() {
        overlayPanel?.orderOut(nil)
    }
    
    private func preferredNotchScreen() -> NSScreen? {
        if let main = NSScreen.main, notchWidth(on: main) != nil {
            return main
        }
        
        return NSScreen.screens.first { notchWidth(on: $0) != nil }
    }
    
    private func notchWidth(on screen: NSScreen) -> CGFloat? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }
        
        guard leftArea.width > 0, rightArea.width > 0 else {
            return nil
        }
        
        let cutoutWidth = screen.frame.width - leftArea.width - rightArea.width
        let isReasonableCutout = cutoutWidth > 70 && cutoutWidth < screen.frame.width * 0.6
        
        return isReasonableCutout ? cutoutWidth : nil
    }
    
    private func panelSize(for notchWidth: CGFloat) -> NSSize {
        let width = min(max(notchWidth + 52, 180), 320)
        return NSSize(width: width, height: 24)
    }
    
    private func panelFrame(for screen: NSScreen, size: NSSize) -> NSRect {
        NSRect(
            x: screen.frame.midX - (size.width / 2),
            y: screen.frame.maxY - size.height - 6,
            width: size.width,
            height: size.height
        )
    }
    
    private func ensurePanel(screen: NSScreen, frame: NSRect) -> NSPanel {
        if let panel = overlayPanel {
            return panel
        }
        
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: NotchGlowView())
        
        overlayPanel = panel
        return panel
    }
}

private struct NotchGlowView: View {
    @State private var glowPhase = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.red.opacity(0.95), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.25))
            )
            .shadow(color: Color.red.opacity(glowPhase ? 0.9 : 0.4), radius: glowPhase ? 12 : 5)
            .shadow(color: Color.red.opacity(glowPhase ? 0.6 : 0.25), radius: glowPhase ? 20 : 10)
            .padding(.horizontal, 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    glowPhase = true
                }
            }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let functionKeyDown = Notification.Name("functionKeyDown")
    static let functionKeyUp = Notification.Name("functionKeyUp")
}

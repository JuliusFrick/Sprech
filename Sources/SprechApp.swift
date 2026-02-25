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
              let notchGeometry = notchGeometry(on: screen) else {
            hide()
            return
        }
        
        let panelSize = panelSize(for: notchGeometry)
        let frame = panelFrame(for: screen, size: panelSize)
        
        let panel = ensurePanel(screen: screen, frame: frame, notchGeometry: notchGeometry)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
    
    private func hide() {
        overlayPanel?.orderOut(nil)
    }
    
    private func preferredNotchScreen() -> NSScreen? {
        if let main = NSScreen.main, notchGeometry(on: main) != nil {
            return main
        }
        
        return NSScreen.screens.first { notchGeometry(on: $0) != nil }
    }
    
    private func notchGeometry(on screen: NSScreen) -> NotchGeometry? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }
        
        guard leftArea.width > 0, rightArea.width > 0 else {
            return nil
        }
        
        let cutoutWidth = screen.frame.width - leftArea.width - rightArea.width
        let isReasonableCutout = cutoutWidth > 70 && cutoutWidth < screen.frame.width * 0.6
        
        guard isReasonableCutout else {
            return nil
        }
        
        let safeInsetTop = screen.safeAreaInsets.top
        let inferredDepth = max(leftArea.height, rightArea.height, safeInsetTop)
        let notchDepth = min(max(inferredDepth + 6, 30), 52)
        
        return NotchGeometry(width: cutoutWidth, depth: notchDepth)
    }
    
    private func panelSize(for notchGeometry: NotchGeometry) -> NSSize {
        let width = min(max(notchGeometry.width + 180, 300), 520)
        let height = min(max(notchGeometry.depth + 96, 112), 180)
        return NSSize(width: width, height: height)
    }
    
    private func panelFrame(for screen: NSScreen, size: NSSize) -> NSRect {
        NSRect(
            x: screen.frame.midX - (size.width / 2),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
    
    private func ensurePanel(screen: NSScreen, frame: NSRect, notchGeometry: NotchGeometry) -> NSPanel {
        let glowView = NotchGlowView(notchWidth: notchGeometry.width, notchDepth: notchGeometry.depth)
        
        if let panel = overlayPanel {
            panel.contentView = NSHostingView(rootView: glowView)
            return panel
        }
        
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: glowView)
        
        overlayPanel = panel
        return panel
    }
}

private struct NotchGeometry {
    let width: CGFloat
    let depth: CGFloat
}

private struct NotchGlowView: View {
    let notchWidth: CGFloat
    let notchDepth: CGFloat
    
    @State private var glowPhase = false
    
    private var notchCornerRadius: CGFloat {
        min(max(notchDepth * 0.36, 8), 16)
    }
    
    var body: some View {
        GeometryReader { proxy in
            let x = (proxy.size.width - notchWidth) / 2
            let notchRect = CGRect(x: x, y: 0, width: notchWidth, height: notchDepth)
            
            ZStack {
                NotchCutoutShape(bottomCornerRadius: notchCornerRadius)
                    .inset(by: -34)
                    .stroke(Color.red.opacity(glowPhase ? 0.40 : 0.18), lineWidth: glowPhase ? 15 : 10)
                    .frame(width: notchRect.width, height: notchRect.height)
                    .position(x: notchRect.midX, y: notchRect.midY)
                    .blur(radius: glowPhase ? 12 : 8)
                
                NotchCutoutShape(bottomCornerRadius: notchCornerRadius)
                    .inset(by: -18)
                    .stroke(Color.red.opacity(glowPhase ? 0.82 : 0.42), lineWidth: glowPhase ? 10 : 6)
                    .frame(width: notchRect.width, height: notchRect.height)
                    .position(x: notchRect.midX, y: notchRect.midY)
                    .blur(radius: glowPhase ? 5 : 3)
                
                NotchCutoutShape(bottomCornerRadius: notchCornerRadius)
                    .stroke(Color.red.opacity(0.96), lineWidth: 1.6)
                    .frame(width: notchRect.width, height: notchRect.height)
                    .position(x: notchRect.midX, y: notchRect.midY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .drawingGroup(opaque: false, colorMode: .linear)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                    glowPhase = true
                }
            }
            .onDisappear {
                glowPhase = false
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NotchCutoutShape: InsettableShape {
    let bottomCornerRadius: CGFloat
    var insetAmount: CGFloat = 0
    
    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(bottomCornerRadius, insetRect.width / 2, insetRect.height * 0.65)
        
        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - radius, y: insetRect.maxY),
            control: CGPoint(x: insetRect.maxX, y: insetRect.maxY)
        )
        path.addLine(to: CGPoint(x: insetRect.minX + radius, y: insetRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX, y: insetRect.maxY - radius),
            control: CGPoint(x: insetRect.minX, y: insetRect.maxY)
        )
        path.closeSubpath()
        return path
    }
    
    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let functionKeyDown = Notification.Name("functionKeyDown")
    static let functionKeyUp = Notification.Name("functionKeyUp")
}

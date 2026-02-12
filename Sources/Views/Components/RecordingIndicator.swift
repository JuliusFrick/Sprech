// RecordingIndicator.swift
// Pulsierender Aufnahme-Indikator

import SwiftUI

/// Roter pulsierender Punkt der Aufnahme signalisiert
struct RecordingIndicator: View {
    /// Größe des Indikators
    var size: CGFloat = 10
    
    /// Animation State
    @State private var isPulsing = false
    
    /// Innerer Punkt-Durchmesser
    private var dotSize: CGFloat { size * 0.7 }
    
    var body: some View {
        ZStack {
            // Äußerer pulsierender Ring
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Zweiter Ring für Tiefe
            Circle()
                .fill(Color.red.opacity(0.2))
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 1.25 : 1.0)
                .opacity(isPulsing ? 0.3 : 0.4)
            
            // Innerer fester Punkt
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.red,
                            Color.red.opacity(0.8)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: dotSize / 2
                    )
                )
                .frame(width: dotSize, height: dotSize)
                .shadow(color: .red.opacity(0.5), radius: 3, x: 0, y: 0)
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .onAppear {
            startPulsing()
        }
    }
    
    private func startPulsing() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: false)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Variants

/// Größerer Aufnahme-Indikator mit Text
struct RecordingIndicatorWithLabel: View {
    var label: String = "Aufnahme"
    
    @State private var opacity: Double = 1.0
    
    var body: some View {
        HStack(spacing: 8) {
            RecordingIndicator(size: 8)
            
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.red)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                opacity = 0.6
            }
        }
    }
}

/// Ring-basierter Indikator (Alternative)
struct RecordingRingIndicator: View {
    var size: CGFloat = 24
    
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.8
    
    var body: some View {
        ZStack {
            // Expandierender Ring
            Circle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            
            // Fester innerer Kreis
            Circle()
                .fill(Color.red)
                .frame(width: size * 0.4, height: size * 0.4)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        withAnimation(
            .easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            ringScale = 2.0
            ringOpacity = 0
        }
    }
}

/// Minimaler Punkt ohne Animation (für statische Anzeige)
struct RecordingDot: View {
    var size: CGFloat = 8
    var color: Color = .red
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
    }
}

// MARK: - Preview

#if DEBUG
struct RecordingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            VStack {
                Text("Standard").font(.caption)
                RecordingIndicator()
            }
            
            VStack {
                Text("Groß").font(.caption)
                RecordingIndicator(size: 16)
            }
            
            VStack {
                Text("Mit Label").font(.caption)
                RecordingIndicatorWithLabel()
            }
            
            VStack {
                Text("Ring-Style").font(.caption)
                RecordingRingIndicator()
            }
            
            VStack {
                Text("Statischer Punkt").font(.caption)
                RecordingDot()
            }
        }
        .padding(40)
        .frame(width: 200)
    }
}
#endif

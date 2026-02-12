// WaveformView.swift
// Animierte Audio-Waveform - Das Herzstück der UI

import SwiftUI

/// Schöne, animierte Waveform die auf Audio-Level reagiert
struct WaveformView: View {
    /// Audio-Pegel von 0.0 (still) bis 1.0 (laut)
    let audioLevel: CGFloat
    
    /// Ob gerade aufgenommen wird
    var isRecording: Bool = false
    
    /// Anzahl der Balken
    var barCount: Int = 14
    
    /// Basis-Höhe im Idle-State
    private let idleHeight: CGFloat = 4
    
    /// Maximale Balken-Höhe
    private let maxHeight: CGFloat = 32
    
    /// Balken-Breite
    private let barWidth: CGFloat = 3
    
    /// Abstand zwischen Balken
    private let barSpacing: CGFloat = 2
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                AudioBar(
                    index: index,
                    totalBars: barCount,
                    audioLevel: audioLevel,
                    isRecording: isRecording,
                    idleHeight: idleHeight,
                    maxHeight: maxHeight,
                    barWidth: barWidth
                )
            }
        }
        .frame(height: maxHeight)
    }
}

// MARK: - Audio Bar

/// Einzelner animierter Balken der Waveform
private struct AudioBar: View {
    let index: Int
    let totalBars: Int
    let audioLevel: CGFloat
    let isRecording: Bool
    let idleHeight: CGFloat
    let maxHeight: CGFloat
    let barWidth: CGFloat
    
    /// Phasenverschiebung für organische Animation
    @State private var phase: Double = 0
    
    /// Berechnet die Höhe basierend auf Position und Audio-Level
    private var calculatedHeight: CGFloat {
        guard isRecording else {
            // Idle: kleine statische Welle
            return idleWaveHeight
        }
        
        // Abstand zur Mitte (0.0 = Mitte, 1.0 = Rand)
        let center = CGFloat(totalBars - 1) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center
        
        // Balken in der Mitte sind höher
        let positionMultiplier = 1.0 - (distanceFromCenter * 0.5)
        
        // Organische Variation pro Balken
        let variation = sin(Double(index) * 0.8 + phase) * 0.3 + 0.7
        
        // Finale Höhe berechnen
        let targetHeight = idleHeight + (maxHeight - idleHeight) * audioLevel * positionMultiplier * CGFloat(variation)
        
        return max(idleHeight, min(maxHeight, targetHeight))
    }
    
    /// Höhe im Idle-Zustand - kleine statische Welle
    private var idleWaveHeight: CGFloat {
        let center = CGFloat(totalBars - 1) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center
        // Kleine Welle in der Mitte höher
        return idleHeight + (6 - distanceFromCenter * 4)
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barGradient)
            .frame(width: barWidth, height: calculatedHeight)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.6, blendDuration: 0.1),
                value: calculatedHeight
            )
            .onAppear {
                // Zufällige Startphase für organischen Look
                phase = Double.random(in: 0...(.pi * 2))
            }
            .onChange(of: audioLevel) { _, _ in
                // Phase leicht verschieben für lebendige Animation
                withAnimation(.linear(duration: 0.1)) {
                    phase += 0.2
                }
            }
    }
    
    /// Gradient von Accent Color (dunkel unten, hell oben)
    private var barGradient: LinearGradient {
        if isRecording {
            return LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.6),
                    Color.accentColor,
                    Color.accentColor.opacity(0.9)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            // Idle: dezentere Farbe
            return LinearGradient(
                colors: [
                    Color.secondary.opacity(0.3),
                    Color.secondary.opacity(0.5)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }
}

// MARK: - Compact Variant

/// Kompakte Waveform für kleine Bereiche (z.B. Menubar)
struct CompactWaveformView: View {
    let audioLevel: CGFloat
    var isRecording: Bool = false
    
    var body: some View {
        WaveformView(
            audioLevel: audioLevel,
            isRecording: isRecording,
            barCount: 7
        )
        .frame(width: 28, height: 16)
        .scaleEffect(0.5)
    }
}

// MARK: - Waveform with Recording Indicator

/// Waveform kombiniert mit Recording-Indikator
struct WaveformWithIndicator: View {
    let audioLevel: CGFloat
    var isRecording: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            if isRecording {
                RecordingIndicator()
            }
            
            WaveformView(
                audioLevel: audioLevel,
                isRecording: isRecording
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // Idle State
            VStack {
                Text("Idle").font(.caption)
                WaveformView(audioLevel: 0, isRecording: false)
            }
            
            // Recording - leise
            VStack {
                Text("Recording - Leise").font(.caption)
                WaveformView(audioLevel: 0.2, isRecording: true)
            }
            
            // Recording - mittel
            VStack {
                Text("Recording - Mittel").font(.caption)
                WaveformView(audioLevel: 0.5, isRecording: true)
            }
            
            // Recording - laut
            VStack {
                Text("Recording - Laut").font(.caption)
                WaveformView(audioLevel: 0.9, isRecording: true)
            }
            
            // Mit Indikator
            VStack {
                Text("Mit Indikator").font(.caption)
                WaveformWithIndicator(audioLevel: 0.6, isRecording: true)
            }
        }
        .padding(40)
        .frame(width: 300)
    }
}
#endif

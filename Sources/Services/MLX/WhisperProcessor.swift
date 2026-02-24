//
//  WhisperProcessor.swift
//  Sprech
//
//  Audio-Preprocessing und Token-Decoding für Whisper MLX
//

import Foundation
import Accelerate
import AVFoundation
import os.log

/// Prozessor für Audio-Vorverarbeitung und Token-Decoding
public final class WhisperProcessor: Sendable {
    
    // MARK: - Constants
    
    /// Whisper erwartet Audio mit 16kHz Sample Rate
    public static let sampleRate: Double = 16000
    
    /// Whisper Chunk-Länge in Sekunden
    public static let chunkLength: Double = 30.0
    
    /// Anzahl Samples pro Chunk
    public static let samplesPerChunk: Int = Int(sampleRate * chunkLength)
    
    /// Mel-Filterbank Parameter
    public static let numMelBins: Int = 80
    public static let hopLength: Int = 160
    public static let fftSize: Int = 400
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.sprech.app", category: "WhisperProcessor")
    private let melFilters: [[Float]]
    private let tokenizer: WhisperTokenizer
    
    // MARK: - Initialization
    
    public init(modelDirectory: URL) throws {
        // Lade Mel-Filter
        let melFiltersURL = modelDirectory.appendingPathComponent("mel_filters.npz")
        self.melFilters = try Self.loadMelFilters(from: melFiltersURL)
        
        // Lade Tokenizer
        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        self.tokenizer = try WhisperTokenizer(from: tokenizerURL)
        
        logger.info("WhisperProcessor initialisiert")
    }
    
    // MARK: - Audio Preprocessing
    
    /// Konvertiert Audio zu 16kHz Mono Float Array
    public func preprocessAudio(_ audioBuffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channelData = audioBuffer.floatChannelData else {
            throw WhisperProcessorError.invalidAudioFormat
        }
        
        let frameLength = Int(audioBuffer.frameLength)
        let channelCount = Int(audioBuffer.format.channelCount)
        
        // Mono-Konvertierung (falls Stereo)
        var samples: [Float]
        if channelCount > 1 {
            samples = [Float](repeating: 0, count: frameLength)
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                samples[i] = sum / Float(channelCount)
            }
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }
        
        // Resampling zu 16kHz falls nötig
        let sourceSampleRate = audioBuffer.format.sampleRate
        if abs(sourceSampleRate - Self.sampleRate) > 1 {
            samples = try resample(samples, from: sourceSampleRate, to: Self.sampleRate)
        }
        
        return samples
    }
    
    /// Resampling mit Accelerate vDSP
    private func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) throws -> [Float] {
        let ratio = targetSR / sourceSR
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)
        
        // Lineares Resampling (für bessere Qualität würde man vDSP_desamp verwenden)
        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
            let index0 = Int(sourceIndex)
            let index1 = min(index0 + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(index0))
            
            output[i] = samples[index0] * (1 - fraction) + samples[index1] * fraction
        }
        
        return output
    }
    
    // MARK: - Mel Spectrogram
    
    /// Generiert Mel-Spektrogramm aus Audio-Samples
    public func melSpectrogram(_ samples: [Float]) -> [[Float]] {
        // Pad Audio zu nächstem Vielfachen von chunk_length
        let paddedLength = max(Self.samplesPerChunk, samples.count)
        var paddedSamples = samples
        if samples.count < paddedLength {
            paddedSamples.append(contentsOf: [Float](repeating: 0, count: paddedLength - samples.count))
        }
        
        // STFT berechnen
        let numFrames = (paddedSamples.count - Self.fftSize) / Self.hopLength + 1
        var spectrogram = [[Float]](repeating: [Float](repeating: 0, count: numFrames), count: Self.numMelBins)
        
        // FFT Setup
        let log2n = vDSP_Length(log2(Float(Self.fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            logger.error("FFT Setup fehlgeschlagen")
            return spectrogram
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Hann-Fenster
        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        
        // Für jeden Frame
        for frameIdx in 0..<numFrames {
            let startIdx = frameIdx * Self.hopLength
            
            // Frame extrahieren und fenstern
            var frame = [Float](repeating: 0, count: Self.fftSize)
            for i in 0..<Self.fftSize {
                if startIdx + i < paddedSamples.count {
                    frame[i] = paddedSamples[startIdx + i] * window[i]
                }
            }
            
            // FFT
            var realp = [Float](repeating: 0, count: Self.fftSize / 2)
            var imagp = [Float](repeating: 0, count: Self.fftSize / 2)
            var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
            
            frame.withUnsafeBufferPointer { framePtr in
                framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.fftSize / 2))
                }
            }
            
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            
            // Magnitude berechnen
            var magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
            vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(Self.fftSize / 2))
            
            // Mel-Filter anwenden
            for melIdx in 0..<Self.numMelBins {
                var sum: Float = 0
                for freqIdx in 0..<min(melFilters[melIdx].count, magnitudes.count) {
                    sum += melFilters[melIdx][freqIdx] * magnitudes[freqIdx]
                }
                // Log-Mel
                spectrogram[melIdx][frameIdx] = log10(max(sum, 1e-10))
            }
        }
        
        // Normalisierung
        normalizeSpectrogram(&spectrogram)
        
        return spectrogram
    }
    
    /// Normalisiert das Spektrogramm
    private func normalizeSpectrogram(_ spectrogram: inout [[Float]]) {
        // Global mean und std
        var allValues: [Float] = []
        for row in spectrogram {
            allValues.append(contentsOf: row)
        }
        
        guard !allValues.isEmpty else { return }
        
        var mean: Float = 0
        var std: Float = 0
        vDSP_meanv(allValues, 1, &mean, vDSP_Length(allValues.count))
        vDSP_normalize(allValues, 1, nil, 1, &mean, &std, vDSP_Length(allValues.count))
        
        if std < 1e-10 { std = 1 }
        
        // Normalisieren
        for i in 0..<spectrogram.count {
            for j in 0..<spectrogram[i].count {
                spectrogram[i][j] = (spectrogram[i][j] - mean) / std
            }
        }
    }
    
    // MARK: - Token Decoding
    
    /// Dekodiert Tokens zu Text
    public func decodeTokens(_ tokens: [Int]) -> String {
        tokenizer.decode(tokens)
    }
    
    /// Enkodiert Text zu Tokens
    public func encodeText(_ text: String) -> [Int] {
        tokenizer.encode(text)
    }
    
    /// Language Token für Sprache
    public func languageToken(for language: WhisperModel.WhisperLanguage) -> Int {
        tokenizer.languageToken(for: language.rawValue)
    }
    
    public var sotToken: Int {
        tokenizer.sotToken
    }
    
    public var transcribeToken: Int {
        tokenizer.transcribeToken
    }
    
    public var noTimestampsToken: Int {
        tokenizer.noTimestampsToken
    }
    
    public var eotToken: Int {
        tokenizer.eotToken
    }
    
    // MARK: - Mel Filter Loading
    
    /// Lädt Mel-Filterbank aus NPZ-Datei
    private static func loadMelFilters(from url: URL) throws -> [[Float]] {
        // Vereinfachte Implementierung - generiere Standard Mel-Filterbank
        // In Produktion würde man die NPZ-Datei parsen
        
        var filters = [[Float]](repeating: [Float](repeating: 0, count: fftSize / 2), count: numMelBins)
        
        let minFreq: Float = 0
        let maxFreq: Float = Float(sampleRate) / 2
        
        // Mel-Frequenz-Konvertierung
        func hzToMel(_ hz: Float) -> Float {
            return 2595 * log10(1 + hz / 700)
        }
        
        func melToHz(_ mel: Float) -> Float {
            return 700 * (pow(10, mel / 2595) - 1)
        }
        
        let minMel = hzToMel(minFreq)
        let maxMel = hzToMel(maxFreq)
        
        let melPoints = (0...numMelBins + 1).map { i in
            melToHz(minMel + Float(i) * (maxMel - minMel) / Float(numMelBins + 1))
        }
        
        let freqPerBin = Float(sampleRate) / Float(fftSize)
        
        for i in 0..<numMelBins {
            let lower = melPoints[i]
            let center = melPoints[i + 1]
            let upper = melPoints[i + 2]
            
            for j in 0..<(fftSize / 2) {
                let freq = Float(j) * freqPerBin
                
                if freq >= lower && freq <= center {
                    filters[i][j] = (freq - lower) / (center - lower)
                } else if freq > center && freq <= upper {
                    filters[i][j] = (upper - freq) / (upper - center)
                }
            }
        }
        
        return filters
    }
}

// MARK: - Whisper Tokenizer

/// Tokenizer für Whisper
public final class WhisperTokenizer: Sendable {
    
    private let vocab: [String: Int]
    private let reverseVocab: [Int: String]
    private let specialTokens: [String: Int]
    
    // Spezielle Token IDs
    public let sotToken: Int
    public let eotToken: Int
    public let translateToken: Int
    public let transcribeToken: Int
    public let noTimestampsToken: Int
    
    public init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode(TokenizerJSON.self, from: data)
        
        // Baue Vocabulary
        var vocab: [String: Int] = [:]
        var reverseVocab: [Int: String] = [:]
        
        if let model = json.model {
            for (token, id) in model.vocab {
                vocab[token] = id
                reverseVocab[id] = token
            }
        }
        
        // Spezielle Tokens
        var specialTokens: [String: Int] = [:]
        if let added = json.addedTokens {
            for token in added {
                specialTokens[token.content] = token.id
                vocab[token.content] = token.id
                reverseVocab[token.id] = token.content
            }
        }
        
        self.vocab = vocab
        self.reverseVocab = reverseVocab
        self.specialTokens = specialTokens
        
        // Standard Token IDs
        self.sotToken = specialTokens["<|startoftranscript|>"] ?? 50258
        self.eotToken = specialTokens["<|endoftext|>"] ?? 50257
        self.translateToken = specialTokens["<|translate|>"] ?? 50359
        self.transcribeToken = specialTokens["<|transcribe|>"] ?? 50358
        self.noTimestampsToken = specialTokens["<|notimestamps|>"] ?? 50363
    }
    
    /// Dekodiert Tokens zu Text
    public func decode(_ tokens: [Int]) -> String {
        var result = ""
        
        for token in tokens {
            guard let text = reverseVocab[token] else { continue }
            
            // Überspringe spezielle Tokens
            if text.hasPrefix("<|") && text.hasSuffix("|>") {
                continue
            }
            
            // GPT-2 Style Tokenizer: Ġ = Leerzeichen-Prefix
            let cleanText = text
                .replacingOccurrences(of: "Ġ", with: " ")
                .replacingOccurrences(of: "Ċ", with: "\n")
            
            result += cleanText
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    /// Enkodiert Text zu Tokens (vereinfacht)
    public func encode(_ text: String) -> [Int] {
        // Vereinfachte Implementierung
        // In Produktion würde man BPE verwenden
        var tokens: [Int] = []
        
        for word in text.components(separatedBy: .whitespaces) {
            if let id = vocab[word] {
                tokens.append(id)
            } else if let id = vocab["Ġ" + word] {
                tokens.append(id)
            }
        }
        
        return tokens
    }
    
    /// Language Token für Sprachcode
    public func languageToken(for languageCode: String) -> Int {
        specialTokens["<|\(languageCode)|>"] ?? specialTokens["<|de|>"] ?? 50261
    }
}

// MARK: - Tokenizer JSON Structure

private struct TokenizerJSON: Codable {
    let model: TokenizerModel?
    let addedTokens: [AddedToken]?
    
    enum CodingKeys: String, CodingKey {
        case model
        case addedTokens = "added_tokens"
    }
}

private struct TokenizerModel: Codable {
    let vocab: [String: Int]
}

private struct AddedToken: Codable {
    let id: Int
    let content: String
}

// MARK: - Errors

public enum WhisperProcessorError: Error, LocalizedError, Sendable {
    case invalidAudioFormat
    case melFilterLoadFailed
    case tokenizerLoadFailed
    case processingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidAudioFormat:
            return "Ungültiges Audio-Format"
        case .melFilterLoadFailed:
            return "Mel-Filter konnten nicht geladen werden"
        case .tokenizerLoadFailed:
            return "Tokenizer konnte nicht geladen werden"
        case .processingFailed(let reason):
            return "Verarbeitung fehlgeschlagen: \(reason)"
        }
    }
}

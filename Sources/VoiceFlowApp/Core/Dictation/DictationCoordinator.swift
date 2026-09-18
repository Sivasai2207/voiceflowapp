import Foundation
import AVFoundation
import Accelerate
import OSLog

@available(macOS 14.0, *)
@MainActor
final class DictationCoordinator: Sendable {
    nonisolated(unsafe) weak var delegate: (any DictationCoordinatorDelegate)?
    
    private let audioCapture = AudioCaptureService()
    private let audioPipeline = AudioPipeline()
    private let outputService = OutputService()
    private let appleProvider: AppleTranscriptionProvider
    private let parakeetProvider: ParakeetTranscriptionProvider
    
    private var currentEngine: TranscriptionEngine = .apple
    private var fallbackEngine: TranscriptionEngine = .parakeet
    private var currentLocale: Locale = .current
    private var outputMode: OutputMode = .pasteAtCursor
    
    init() {
        print("🏗️ DictationCoordinator.init() START")
        self.appleProvider = AppleTranscriptionProvider()
        print("✅ AppleTranscriptionProvider created")
        self.parakeetProvider = ParakeetTranscriptionProvider.shared
        print("✅ ParakeetTranscriptionProvider created")
        print("🏗️ DictationCoordinator.init() COMPLETE")
    }
    
    private var isRecording = false
    private var isProcessing = false
    private var currentTranscript = ""
    private var appleResultsTask: Task<Void, Never>?
    private var startTime: Date?
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "DictationCoordinator")
    
    func startRecording(
        engine: TranscriptionEngine,
        fallbackEngine: TranscriptionEngine,
        locale: Locale,
        outputMode: OutputMode
    ) async throws {
        print("🎙️ DictationCoordinator.startRecording() called (engine: \(engine))")
        guard !isRecording else { 
            print("⚠️ Already recording, returning")
            return 
        }
        
        self.currentEngine = engine
        self.fallbackEngine = fallbackEngine
        self.currentLocale = locale
        self.outputMode = outputMode
        
        print("📝 Logger: Starting dictation with \(engine.rawValue), fallback: \(fallbackEngine.rawValue)")
        logger.info("Starting dictation with \(engine.rawValue), fallback: \(fallbackEngine.rawValue)")
        
        let initialEngine = engine
        Task { @MainActor in
            delegate?.didChangeEngine(initialEngine)
        }
        
        do {
            try await prepareEngine(engine, locale: locale)
        } catch {
            logger.error("Primary engine preparation failed: \(error)")
            if fallbackEngine != engine {
                let fbEngine = fallbackEngine
                Task { @MainActor in
                    delegate?.didChangeEngine(fbEngine)
                }
                try await prepareEngine(fallbackEngine, locale: locale)
            } else {
                throw error
            }
        }
        
        let sourceFormat = await audioCapture.currentFormat
        if let format = sourceFormat {
            await audioPipeline.prepare(forAppleFormat: format, sourceFormat: format)
        }
        
        startTime = Date()
        isRecording = true
        currentTranscript = ""

        await outputService.captureTargetContext()
        
        switch currentEngine {
        case .apple:
            try await appleProvider.startRecording()
        case .parakeet:
            try await parakeetProvider.startRecording()
        }
        
        try await audioCapture.startRecording { [weak self] samples, format in
            Task { await self?.handleAudioSamples(samples, format: format) }
        }
        
        logger.info("Recording started successfully")
    }
    
    private func prepareEngine(_ engine: TranscriptionEngine, locale: Locale) async throws {
        switch engine {
        case .apple:
            try await appleProvider.prepare(locale: locale)
        case .parakeet:
            try await parakeetProvider.prepare(locale: locale)
        }
    }
    
    func prewarm(engine: TranscriptionEngine, fallbackEngine: TranscriptionEngine, locale: Locale) async {
        try? await prepareEngine(engine, locale: locale)
        if fallbackEngine != engine {
            try? await prepareEngine(fallbackEngine, locale: locale)
        }
    }
    
    private func handleAudioSamples(_ samples: [Float], format: AVAudioFormat) async {
        guard isRecording else { return }
        
        let level = calculateAudioLevel(from: samples)
        Task { @MainActor in
            delegate?.didUpdateAudioLevel(level)
        }
        
        let parakeetSamples = await audioPipeline.processForParakeetSamples(samples, format: format)
        
        do {
            if currentEngine == .apple, !parakeetSamples.isEmpty {
                try await appleProvider.appendAudioSamples(parakeetSamples)
            } else if currentEngine == .parakeet, !parakeetSamples.isEmpty {
                try await parakeetProvider.appendAudioSamples(parakeetSamples)
            }
        } catch {
            logger.error("Audio processing error: \(error)")
        }
    }
    
    private func calculateAudioLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var sum: Float = 0
        vDSP_measqv(samples, 1, &sum, vDSP_Length(samples.count))
        let rms = sqrt(sum / Float(samples.count))
        
        return min(max(rms * 10, 0), 1)
    }
    
    func stopRecording() async throws -> String {
        guard isRecording else { return "" }
        
        isRecording = false
        isProcessing = true
        
        await audioCapture.stopRecording()
        
        var rawTranscript = ""
        
        do {
            rawTranscript = try await transcribeWithCurrentEngine()
        } catch {
            logger.error("Primary transcription failed: \(error)")
            
            if fallbackEngine != currentEngine {
                let fbEngine = fallbackEngine
                logger.info("Attempting fallback to \(fbEngine.rawValue)")
                Task { @MainActor in
                    delegate?.didChangeEngine(fbEngine)
                }
                
                do {
                    rawTranscript = try await transcribeWithFallback()
                } catch {
                    logger.error("Fallback transcription failed: \(error)")
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // If primary engine (Apple Speech) returned empty text, invoke fallback engine (Parakeet) on retained audio!
        if rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fallbackEngine != currentEngine {
            logger.info("Primary engine (\(self.currentEngine.rawValue)) produced empty transcript; attempting fallback to \(self.fallbackEngine.rawValue)")
            if let fallbackText = try? await transcribeWithFallback(), !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.info("Fallback engine (\(self.fallbackEngine.rawValue)) succeeded: \(fallbackText)")
                rawTranscript = fallbackText
            }
        }
        
        await audioPipeline.clearRetainedAudio()
        
        // Wispr Flow AI text polishing (removes fillers, fixes stutters, adds punctuation, fixes grammar/contractions)
        let autoPunct = await MainActor.run { SettingsStore.shared.autoPunctuation }
        let dictionaryEntries = DictionaryStore.shared.entries
        let polished = SpeechPolishingService.shared.polish(
            transcript: rawTranscript,
            autoPunctuation: autoPunct,
            dictionaryEntries: dictionaryEntries
        )
        
        currentTranscript = polished
        Task { @MainActor in
            self.delegate?.didUpdateTranscript(polished, isFinal: true)
        }
        
        await outputService.insertText(polished, mode: outputMode)
        isProcessing = false
        return polished
    }
    
    private func transcribeWithCurrentEngine() async throws -> String {
        switch currentEngine {
        case .apple:
            return try await appleProvider.stopRecording()
        case .parakeet:
            return try await parakeetProvider.stopRecording()
        }
    }
    
    private func transcribeWithFallback() async throws -> String {
        let retainedAudio = await audioPipeline.getRetainedAudio()
        guard !retainedAudio.isEmpty else {
            throw TranscriptionError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio retained for fallback"]))
        }
        
        try await prepareEngine(fallbackEngine, locale: currentLocale)

        switch fallbackEngine {
        case .apple:
            try await appleProvider.startRecording()
            try await appleProvider.appendAudioSamples(retainedAudio)
            return try await appleProvider.stopRecording()
        case .parakeet:
            try await parakeetProvider.startRecording()
            try await parakeetProvider.appendAudioSamples(retainedAudio)
            return try await parakeetProvider.stopRecording()
        }
    }
    
    func cancelRecording() async {
        guard isRecording || isProcessing else { return }
        
        isRecording = false
        isProcessing = false
        
        await audioCapture.stopRecording()
        
        do {
            try await appleProvider.cancelRecording()
            try await parakeetProvider.cancelRecording()
        } catch {
            logger.error("Cancel error: \(error)")
        }
        
        await audioPipeline.clearRetainedAudio()
        currentTranscript = ""
    }
    
    func updateTranscript(_ transcript: String, isFinal: Bool) {
        currentTranscript = transcript
        Task { @MainActor in
            self.delegate?.didUpdateTranscript(transcript, isFinal: isFinal)
        }
    }
}

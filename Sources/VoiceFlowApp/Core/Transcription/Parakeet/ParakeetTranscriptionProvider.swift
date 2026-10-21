import Foundation
import FluidAudio
import AVFoundation
import OSLog

@MainActor
final class ParakeetTranscriptionProvider: TranscriptionProvider {
    static let shared = ParakeetTranscriptionProvider()
    
    private var asrManager: AsrManager?
    private var models: AsrModels?
    private var audioBuffer: [Float] = []
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "ParakeetTranscription")
    private var isPrepared = false
    
    private init() {
        print("🏗️ ParakeetTranscriptionProvider.init() START")
        print("🏗️ ParakeetTranscriptionProvider.init() COMPLETE")
    }
    
    nonisolated var isAvailable: Bool {
        get async { 
            print("🔍 Parakeet: isAvailable check")
            return true 
        }
    }
    
    nonisolated var supportedLocales: [Locale] {
        get async {
            print("🔍 Parakeet: supportedLocales check")
            return [
                Locale(identifier: "en_US"),
                Locale(identifier: "es_ES"),
                Locale(identifier: "fr_FR"),
                Locale(identifier: "de_DE"),
                Locale(identifier: "it_IT"),
                Locale(identifier: "pt_PT"),
                Locale(identifier: "nl_NL"),
                Locale(identifier: "pl_PL"),
                Locale(identifier: "ru_RU"),
                Locale(identifier: "zh_CN"),
                Locale(identifier: "ja_JP"),
                Locale(identifier: "ko_KR"),
            ]
        }
    }
    
    func prepare(locale: Locale) async throws {
        print("🎙️ Parakeet.prepare() called for locale: \(locale.identifier)")
        guard !isPrepared else { 
            print("⚠️ Parakeet already prepared")
            return 
        }
        
        let modelURL = await ModelStore.shared.parakeetModelURL()
        print("📦 Parakeet model URL: \(modelURL.path)")
        let fileManager = FileManager.default
        
        // Downloads are initiated only from the explicit model-download screen.
        if !fileManager.fileExists(atPath: modelURL.path) {
            throw TranscriptionError.modelNotInstalled
        }
        print("✅ Parakeet model already exists")
        
        let configuration = AsrModels.defaultConfiguration()
        models = try await AsrModels.load(from: modelURL, configuration: configuration, version: .v3)
        
        let manager = AsrManager()
        try await manager.initialize(models: models!)
        
        self.asrManager = manager
        self.isPrepared = true
        
        logger.info("Parakeet model loaded successfully")
    }
    
    func startRecording() async throws {
        audioBuffer.removeAll(keepingCapacity: true)
        audioBuffer.reserveCapacity(16000 * 60)
    }
    
    func stopRecording() async throws -> String {
        guard let manager = asrManager else {
            throw TranscriptionError.engineUnavailable
        }
        
        guard !audioBuffer.isEmpty else { return "" }
        
        let format = AVAudioFormat.init(standardFormatWithSampleRate: 16000, channels: 1)!
        let frameCount = AVAudioFrameCount(audioBuffer.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TranscriptionError.audioFormatUnsupported
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(from: self.audioBuffer, count: audioBuffer.count)
        }
        
        // `AsrManager.transcribe` is a @concurrent method, so it runs off the main
        // actor. `buffer` is freshly built above and not used afterwards, and the
        // manager is designed to be driven from a single caller, so handing them
        // across the isolation boundary here is safe.
        nonisolated(unsafe) let sendableBuffer = buffer
        nonisolated(unsafe) let sendableManager = manager
        let asrResult = try await sendableManager.transcribe(sendableBuffer, source: .system)
        
        audioBuffer.removeAll(keepingCapacity: false)
        
        return asrResult.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    func cancelRecording() async throws {
        audioBuffer.removeAll(keepingCapacity: false)
    }
    
    func appendAudioSamples(_ samples: [Float]) async throws {
        audioBuffer.append(contentsOf: samples)
    }
}

private actor ModelDownloader {
    func downloadParakeetModel(to url: URL) async throws {
        let repoURL = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main"
        let files = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
            "parakeet_vocab.json"
        ]
        
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        
        for file in files {
            let fileURL = url.appendingPathComponent(file)
            let downloadURL = URL(string: "\(repoURL)/\(file)")!
            
            let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}

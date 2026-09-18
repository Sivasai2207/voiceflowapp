import Foundation
import AVFoundation
import OSLog

actor AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var outputFormat: AVAudioFormat?
    private var audioBufferHandler: (@Sendable ([Float], AVAudioFormat) -> Void)?
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "AudioCapture")
    private var isRecording = false
    
    func startRecording(handler: @escaping @Sendable ([Float], AVAudioFormat) -> Void) async throws {
        print("🎤 AudioCaptureService.startRecording() called")
        guard !isRecording else { 
            print("⚠️ Already recording, returning")
            return 
        }
        
        print("🎤 Creating AVAudioEngine...")
        let engine = AVAudioEngine()
        print("🎤 Getting input node...")
        let input = engine.inputNode
        print("🎤 Getting output format...")
        let format = input.outputFormat(forBus: 0)
        print("🎤 Format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        guard format.channelCount > 0, format.sampleRate > 0 else {
            print("❌ Invalid audio format")
            throw TranscriptionError.audioFormatUnsupported
        }
        
        self.audioEngine = engine
        self.inputNode = input
        self.outputFormat = format
        self.audioBufferHandler = handler
        self.isRecording = true
        
        print("🎤 Installing tap on bus 0...")
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = AudioCaptureService.extractFloatSamples(from: buffer)
            handler(samples, format)
        }
        print("✅ Tap installed")
        
        print("🎤 Preparing engine...")
        engine.prepare()
        print("✅ Engine prepared")
        
        print("🎤 Starting engine...")
        try engine.start()
        print("✅ Engine started successfully")
        
        logger.info("Audio capture started: \(format.sampleRate)Hz, \(format.channelCount)ch")
        print("✅ Audio capture started")
    }
    
    nonisolated static func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        
        audioEngine = nil
        inputNode = nil
        outputFormat = nil
        audioBufferHandler = nil
        isRecording = false
        
        logger.info("Audio capture stopped")
    }
    
    var currentFormat: AVAudioFormat? {
        outputFormat
    }
    
    var recordingState: Bool {
        isRecording
    }
}

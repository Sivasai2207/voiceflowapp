import Foundation
import AVFoundation
import Speech
import OSLog

actor AppleTranscriptionProvider: TranscriptionProvider {
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "AppleTranscription")
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isPrepared = false
    private var currentLocale: Locale = .current
    private var latestTranscript: String = ""
    private var isFinished: Bool = false
    private var completionContinuation: CheckedContinuation<String, Error>?
    
    nonisolated var isAvailable: Bool {
        get async {
            let status = SFSpeechRecognizer.authorizationStatus()
            return status == .authorized || status == .notDetermined
        }
    }
    
    nonisolated var supportedLocales: [Locale] {
        get async {
            Array(SFSpeechRecognizer.supportedLocales())
        }
    }
    
    init() {
        self.currentLocale = Locale.current
        self.recognizer = SFSpeechRecognizer(locale: currentLocale)
    }
    
    func prepare(locale: Locale) async throws {
        self.currentLocale = locale
        let newRecognizer = SFSpeechRecognizer(locale: locale)
        guard let r = newRecognizer, r.isAvailable else {
            logger.warning("SFSpeechRecognizer not available for locale \(locale.identifier), falling back to system")
            self.recognizer = SFSpeechRecognizer()
            self.isPrepared = (self.recognizer != nil)
            return
        }
        self.recognizer = r
        self.isPrepared = true
        logger.info("Apple Speech recognizer prepared for locale: \(locale.identifier)")
    }
    
    func startRecording() async throws {
        guard let recognizer = self.recognizer else {
            throw TranscriptionError.engineUnavailable
        }
        
        cancelCurrentTask()
        latestTranscript = ""
        isFinished = false
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        
        // Use on-device recognition if available for maximum speed and privacy
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        self.recognitionRequest = request
        
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcriptText = result?.bestTranscription.formattedString ?? ""
            let finalFlag = result?.isFinal ?? false
            let errDesc = error?.localizedDescription
            let nsErr = error as NSError?
            let isNormalCompletion = nsErr?.code == 216 || nsErr?.code == 203 || nsErr?.domain == "kAFAssistantErrorDomain"
            
            Task { [weak self] in
                await self?.handleExtractedResult(
                    transcript: transcriptText,
                    isFinal: finalFlag,
                    errorDescription: errDesc,
                    isNormalCompletion: isNormalCompletion
                )
            }
        }
        
        logger.info("Apple Speech recognition task started")
    }
    
    private func handleExtractedResult(
        transcript: String,
        isFinal: Bool,
        errorDescription: String?,
        isNormalCompletion: Bool
    ) {
        if !transcript.isEmpty {
            self.latestTranscript = transcript
        }
        
        if isFinal || isNormalCompletion {
            self.isFinished = true
            if let cont = self.completionContinuation {
                self.completionContinuation = nil
                cont.resume(returning: self.latestTranscript)
            }
        } else if let err = errorDescription {
            if let cont = self.completionContinuation {
                self.completionContinuation = nil
                if !self.latestTranscript.isEmpty {
                    cont.resume(returning: self.latestTranscript)
                } else {
                    cont.resume(throwing: TranscriptionError.transcriptionFailed(NSError(domain: "AppleSpeech", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                }
            }
        }
    }
    
    func stopRecording() async throws -> String {
        recognitionRequest?.endAudio()
        
        // If we already have a final transcript or task finished
        if isFinished && !latestTranscript.isEmpty {
            let result = latestTranscript
            cancelCurrentTask()
            return result
        }
        
        // Rapid final recognition pass: wait only 180ms if text already captured, or 350ms if empty
        let timeoutNs: UInt64 = latestTranscript.isEmpty ? 350_000_000 : 180_000_000
        
        return try await withCheckedThrowingContinuation { continuation in
            self.completionContinuation = continuation
            
            // Timeout task
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNs)
                guard let self else { return }
                await self.handleTimeout()
            }
        }
    }
    
    private func handleTimeout() {
        if let cont = self.completionContinuation {
            self.completionContinuation = nil
            // Return whatever transcript we have gathered
            cont.resume(returning: self.latestTranscript)
        }
        cancelCurrentTask()
    }
    
    func cancelRecording() async throws {
        cancelCurrentTask()
    }
    
    func appendAudioSamples(_ samples: [Float]) async throws {
        guard let request = recognitionRequest, !samples.isEmpty else { return }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(from: samples, count: samples.count)
        }
        
        request.append(buffer)
    }
    
    private func cancelCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isFinished = false
    }
}
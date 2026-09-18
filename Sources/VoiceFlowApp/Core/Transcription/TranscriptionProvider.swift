import Foundation
import Speech
import AVFoundation

protocol TranscriptionProvider: Sendable {
    var isAvailable: Bool { get async }
    var supportedLocales: [Locale] { get async }
    
    func prepare(locale: Locale) async throws
    func startRecording() async throws
    func stopRecording() async throws -> String
    func cancelRecording() async throws
    func appendAudioSamples(_ samples: [Float]) async throws
}

@MainActor
protocol DictationCoordinatorDelegate: AnyObject, Sendable {
    func didUpdateTranscript(_ transcript: String, isFinal: Bool)
    func didChangeEngine(_ engine: TranscriptionEngine)
    func didUpdateAudioLevel(_ level: Float)
}

enum TranscriptionError: LocalizedError {
    case engineUnavailable
    case localeNotSupported(Locale)
    case modelNotInstalled
    case recordingFailed(Error)
    case transcriptionFailed(Error)
    case permissionDenied
    case audioFormatUnsupported
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .engineUnavailable: return "Transcription engine is not available"
        case .localeNotSupported(let locale): return "Locale \(locale.identifier) is not supported"
        case .modelNotInstalled: return "Required model is not installed"
        case .recordingFailed(let error): return "Recording failed: \(error.localizedDescription)"
        case .transcriptionFailed(let error): return "Transcription failed: \(error.localizedDescription)"
        case .permissionDenied: return "Microphone permission denied"
        case .audioFormatUnsupported: return "Audio format not supported"
        case .cancelled: return "Recording was cancelled"
        }
    }
}
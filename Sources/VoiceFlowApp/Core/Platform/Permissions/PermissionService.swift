import Foundation
import AVFoundation
import Speech
@preconcurrency import ApplicationServices
import AppKit
import OSLog

actor PermissionService {
    static let shared = PermissionService()
    
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "Permissions")
    
    enum PermissionType: String, CaseIterable {
        case microphone = "Microphone"
        case accessibility = "Accessibility"
        case speechRecognition = "Speech Recognition"
    }
    
    func checkAllPermissions() async -> PermissionStatus {
        let micStatus = checkMicrophonePermission()
        let accessibilityStatus = checkAccessibilityPermission()
        let speechStatus = checkSpeechRecognitionPermission()
        
        var granted: [String] = []
        var denied: [String] = []
        
        if micStatus { granted.append(PermissionType.microphone.rawValue) } else { denied.append(PermissionType.microphone.rawValue) }
        if accessibilityStatus { granted.append(PermissionType.accessibility.rawValue) } else { denied.append(PermissionType.accessibility.rawValue) }
        if speechStatus { granted.append(PermissionType.speechRecognition.rawValue) } else { denied.append(PermissionType.speechRecognition.rawValue) }
        
        if denied.isEmpty {
            return .granted
        } else if granted.isEmpty {
            return .denied(denied)
        } else {
            return .partial(granted, denied)
        }
    }
    
    nonisolated func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }
    
    nonisolated func checkAccessibilityPermission() -> Bool {
        let options: [CFString: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    nonisolated func checkSpeechRecognitionPermission() -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        return status == .authorized
    }
    
    func requestMicrophonePermission() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    nonisolated func requestAccessibilityPermission() {
        let options: [CFString: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    nonisolated func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    nonisolated func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    nonisolated func openSpeechRecognitionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
}
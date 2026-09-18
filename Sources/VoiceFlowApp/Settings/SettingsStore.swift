import Foundation
import SwiftUI
import KeyboardShortcuts

enum HotkeyMode: String, CaseIterable, Identifiable {
    case pushToTalk = "Push-to-Talk (Hold)"
    case continuous = "Continuous (Toggle)"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .pushToTalk: return "Hold the hotkey to record, release to transcribe"
        case .continuous: return "Press once to start, press again to stop"
        }
    }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case teal = "Teal (Default)"
    case blue = "Blue"
    case purple = "Purple"
    case orange = "Orange"
    case graphite = "Graphite"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .teal: return Color(red: 0.0, green: 0.75, blue: 0.85)
        case .blue: return Color.blue
        case .purple: return Color.purple
        case .orange: return Color.orange
        case .graphite: return Color.gray
        }
    }
}

extension KeyboardShortcuts.Name {
    static let startDictation = Self("startDictation", initial: .init(.space, modifiers: [.option]))
    static let toggleDictation = Self("toggleDictation", initial: .init(.space, modifiers: [.command, .option]))
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    @AppStorage("selectedEngine") var selectedEngineRaw: String = TranscriptionEngine.apple.rawValue
    @AppStorage("fallbackEngine") var fallbackEngineRaw: String = TranscriptionEngine.parakeet.rawValue
    @AppStorage("outputMode") var outputModeRaw: String = OutputMode.pasteAtCursor.rawValue
    @AppStorage("selectedLocale") var selectedLocaleIdentifier: String = Locale.current.identifier
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showHUD") var showHUD: Bool = true
    @AppStorage("autoPunctuation") var autoPunctuation: Bool = true
    @AppStorage("maxRecordingDuration") var maxRecordingDuration: Double = 120
    @AppStorage("hotkeyMode") var hotkeyModeRaw: String = HotkeyMode.pushToTalk.rawValue
    @AppStorage("useDefaultHotkeys") var useDefaultHotkeys: Bool = true
    
    @AppStorage("accentColor") var accentColorRaw: String = AppAccentColor.teal.rawValue
    @AppStorage("selectedAudioDeviceName") var selectedAudioDeviceName: String = "Default"
    @AppStorage("noiseReduction") var noiseReduction: Bool = true
    @AppStorage("voiceActivityDetection") var voiceActivityDetection: Bool = true
    @AppStorage("restoreClipboard") var restoreClipboard: Bool = true
    @AppStorage("autoDismissHUD") var autoDismissHUD: Bool = true
    
    var selectedEngine: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: selectedEngineRaw) ?? .apple }
        set {
            objectWillChange.send()
            selectedEngineRaw = newValue.rawValue
        }
    }
    
    var fallbackEngine: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: fallbackEngineRaw) ?? .parakeet }
        set {
            objectWillChange.send()
            fallbackEngineRaw = newValue.rawValue
        }
    }
    
    var outputMode: OutputMode {
        get { OutputMode(rawValue: outputModeRaw) ?? .pasteAtCursor }
        set {
            objectWillChange.send()
            outputModeRaw = newValue.rawValue
        }
    }
    
    var selectedLocale: Locale {
        get { Locale(identifier: selectedLocaleIdentifier) }
        set {
            objectWillChange.send()
            selectedLocaleIdentifier = newValue.identifier
        }
    }
    
    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: hotkeyModeRaw) ?? .pushToTalk }
        set {
            objectWillChange.send()
            hotkeyModeRaw = newValue.rawValue
            NotificationCenter.default.post(
                name: Notification.Name.hotkeyModeChanged,
                object: newValue
            )
        }
    }
    
    var accentColor: AppAccentColor {
        get { AppAccentColor(rawValue: accentColorRaw) ?? .teal }
        set {
            objectWillChange.send()
            accentColorRaw = newValue.rawValue
        }
    }
    
    private init() {}
    
    func resetToDefaults() {
        objectWillChange.send()
        selectedEngineRaw = TranscriptionEngine.apple.rawValue
        fallbackEngineRaw = TranscriptionEngine.parakeet.rawValue
        outputModeRaw = OutputMode.pasteAtCursor.rawValue
        selectedLocaleIdentifier = Locale.current.identifier
        launchAtLogin = false
        showHUD = true
        autoPunctuation = true
        maxRecordingDuration = 120
        hotkeyModeRaw = HotkeyMode.pushToTalk.rawValue
        useDefaultHotkeys = true
        accentColorRaw = AppAccentColor.teal.rawValue
        selectedAudioDeviceName = "Default"
        noiseReduction = true
        voiceActivityDetection = true
        restoreClipboard = true
        autoDismissHUD = true
    }
}

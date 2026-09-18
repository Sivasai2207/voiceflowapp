import SwiftUI
import Combine
import KeyboardShortcuts

@available(macOS 14.0, *)
@MainActor
final class AppModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var currentTranscript = ""
    @Published var lastTranscript = ""
    @Published var audioLevel: Float = 0.0
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 40)
    @Published var selectedEngine: TranscriptionEngine = SettingsStore.shared.selectedEngine
    @Published var fallbackEngine: TranscriptionEngine = SettingsStore.shared.fallbackEngine
    @Published var outputMode: OutputMode = SettingsStore.shared.outputMode
    @Published var selectedLocale: Locale = SettingsStore.shared.selectedLocale
    @Published var isModelDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var showingError = false
    @Published var permissionStatus: PermissionStatus = .unknown
    @Published var recordingDuration: TimeInterval = 0
    @Published var hotkeyMode: HotkeyMode = .pushToTalk
    @Published var useDefaultHotkeys: Bool = true
    
    @Published var isContinuousRecording = false
    
    private var recordingTimer: Timer?
    private let coordinator = DictationCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var isStarting = false
    private var stopRequestedWhileStarting = false
    private var startTask: Task<Void, Never>?
    
    init() {
        print("🏗️ AppModel.init() START")
        coordinator.delegate = self
        setupHotkeyObservers()
        Task {
            print("🔍 AppModel: starting async init")
            await checkPermissions()
            print("✅ AppModel: permissions checked")
            await checkModelAvailability()
            print("✅ AppModel: model availability checked")
            applyHotkeySettings()
            print("✅ AppModel: hotkey settings applied")
        }
        print("🏗️ AppModel.init() COMPLETE")
    }
    
    private func setupHotkeyObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name.hotkeyModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let mode = notification.object as? HotkeyMode {
                Task { @MainActor [weak self] in
                    self?.hotkeyMode = mode
                    self?.applyHotkeySettings()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name.defaultHotkeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let useDefaults = notification.object as? Bool {
                Task { @MainActor [weak self] in
                    self?.useDefaultHotkeys = useDefaults
                    self?.applyHotkeySettings()
                }
            }
        }
    }
    
    private func applyHotkeySettings() {
        let settings = SettingsStore.shared
        hotkeyMode = settings.hotkeyMode
        useDefaultHotkeys = settings.useDefaultHotkeys
        
HotkeyService.shared.updateMode(
            settings.hotkeyMode,
            useDefaults: settings.useDefaultHotkeys
        )
    }
    
    func startRecording(isContinuous: Bool = false) {
        guard !isRecording && !isStarting else { return }
        errorMessage = nil
        isStarting = true
        stopRequestedWhileStarting = false
        if isContinuous {
            isContinuousRecording = true
        }

        let settings = SettingsStore.shared
        selectedEngine = settings.selectedEngine
        fallbackEngine = settings.fallbackEngine
        outputMode = settings.outputMode
        selectedLocale = settings.selectedLocale
        
        startTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coordinator.startRecording(
                    engine: settings.selectedEngine,
                    fallbackEngine: settings.fallbackEngine,
                    locale: settings.selectedLocale,
                    outputMode: settings.outputMode
                )
                self.isStarting = false
                self.isRecording = true
                self.startRecordingTimer()
                
                // If user released the key before starting finished, stop now
                if self.stopRequestedWhileStarting {
                    self.stopRequestedWhileStarting = false
                    self.stopRecording()
                }
            } catch {
                self.isStarting = false
                self.isRecording = false
                self.isContinuousRecording = false
                self.stopRequestedWhileStarting = false
                self.showError(error.localizedDescription)
            }
        }
    }
    
    func stopRecording() {
        isContinuousRecording = false
        
        // If still initializing the recording engine, flag to stop immediately on finish
        if isStarting {
            stopRequestedWhileStarting = true
            return
        }
        
        guard isRecording else { return }
        
        isRecording = false
        isProcessing = true
        stopRecordingTimer()
        
        Task {
            do {
                let transcript = try await coordinator.stopRecording()
                currentTranscript = transcript
                lastTranscript = transcript
                DictationHistoryStore.shared.add(transcript)
                isProcessing = false
            } catch {
                isProcessing = false
                showError(error.localizedDescription)
            }
        }
    }
    
    func startPushToTalk() {
        guard !isContinuousRecording else { return }
        startRecording(isContinuous: false)
    }
    
    func stopPushToTalk() {
        // Lifting fingers in continuous mode MUST NOT stop dictation
        guard !isContinuousRecording else { return }
        stopRecording()
    }
    
    func toggleContinuous() {
        if isRecording || isStarting {
            stopRecording()
        } else {
            startRecording(isContinuous: true)
        }
    }
    
    func toggleRecording() {
        if isRecording || isStarting {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func cancelRecording() {
        guard isRecording || isProcessing || isStarting else { return }
        
        isContinuousRecording = false
        isStarting = false
        stopRequestedWhileStarting = false
        startTask?.cancel()
        startTask = nil
        
        Task {
            await coordinator.cancelRecording()
            isRecording = false
            isProcessing = false
            currentTranscript = ""
            stopRecordingTimer()
        }
    }
    
    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordingDuration += 0.1
                if self.recordingDuration >= SettingsStore.shared.maxRecordingDuration {
                    self.stopRecording()
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func refreshPermissions() async {
        permissionStatus = await PermissionService.shared.checkAllPermissions()
    }
    
    private func checkPermissions() async {
        await refreshPermissions()
    }
    
    private func checkModelAvailability() async {
        let settings = SettingsStore.shared
        await coordinator.prewarm(
            engine: settings.selectedEngine,
            fallbackEngine: settings.fallbackEngine,
            locale: settings.selectedLocale
        )
        
        Task.detached(priority: .userInitiated) {
            let installed = await ModelStore.shared.isParakeetModelInstalled()
            if installed {
                do {
                    try await ParakeetTranscriptionProvider.shared.prepare(locale: Locale(identifier: "en_US"))
                    print("🚀 Parakeet model pre-warmed and ready")
                } catch {
                    print("⚠️ Parakeet pre-warm: \(error)")
                }
            }
        }
    }
    
    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    func dismissError() {
        showingError = false
        errorMessage = nil
    }
    
    func copyLastTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }
}

@available(macOS 14.0, *)
extension AppModel: DictationCoordinatorDelegate {
    func didUpdateTranscript(_ transcript: String, isFinal: Bool) {
        currentTranscript = transcript
        if isFinal {
            lastTranscript = transcript
        }
    }
    
    func didChangeEngine(_ engine: TranscriptionEngine) {
        selectedEngine = engine
    }
    
    func didUpdateAudioLevel(_ level: Float) {
        audioLevel = level
        audioLevels.append(level)
        if audioLevels.count > 40 {
            audioLevels.removeFirst()
        }
    }
}

extension Notification.Name {
    static let hotkeyModeChanged = Notification.Name("VoiceFlowApp.hotkeyModeChanged")
    static let defaultHotkeysChanged = Notification.Name("VoiceFlowApp.defaultHotkeysChanged")
}

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case apple = "Apple Speech"
    case parakeet = "Parakeet (Local)"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .parakeet: return "waveform.circle.fill"
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case pasteAtCursor = "Paste at Cursor"
    case clipboardOnly = "Copy to Clipboard"
    
    var id: String { rawValue }
}

enum PermissionStatus: Equatable {
    case unknown
    case granted
    case denied([String])
    case partial([String], [String])
    
    var isFullyGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

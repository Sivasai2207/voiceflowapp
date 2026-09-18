import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AVFoundation

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case audio
    case transcription
    case output
    case shortcuts
    case dictionary
    case history
    case privacy
    case about

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .audio: "waveform"
        case .transcription: "text.bubble.fill"
        case .output: "doc.on.clipboard.fill"
        case .shortcuts: "keyboard.fill"
        case .dictionary: "text.book.closed.fill"
        case .history: "clock.arrow.circlepath"
        case .privacy: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .general: .blue
        case .audio: .purple
        case .transcription: .cyan
        case .output: .orange
        case .shortcuts: .green
        case .dictionary: .pink
        case .history: .mint
        case .privacy: .indigo
        case .about: .gray
        }
    }
}

@available(macOS 14.0, *)
struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var dictionary = DictionaryStore.shared
    @ObservedObject private var history = DictationHistoryStore.shared
    
    @State private var showingModelDownload = false
    @State private var showingModelDeleteConfirmation = false
    @State private var showingHistoryDeleteConfirmation = false
    @State private var showingDictionaryDeleteConfirmation = false
    @State private var isParakeetModelInstalled = false
    @State private var parakeetModelSize: Int64 = 0
    @State private var selectedSection: SettingsSection? = .general
    @State private var dictionaryWord = ""
    
    // Live mic test state
    @State private var isTestingMic = false
    @State private var testAudioLevel: Float = 0.0
    @State private var testEngine: AVAudioEngine?
    
    // Privacy live statuses
    @State private var micGranted = PermissionService.shared.checkMicrophonePermission()
    @State private var axGranted = PermissionService.shared.checkAccessibilityPermission()
    @State private var speechGranted = PermissionService.shared.checkSpeechRecognitionPermission()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Sidebar Brand Header
                HStack(spacing: 12) {
                    AppIconView(size: 32, showShadow: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VoiceFlow")
                            .font(.system(size: 14, weight: .bold))
                        Text("v1.0.0")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                List(SettingsSection.allCases, selection: $selectedSection) { section in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(section.iconColor.gradient)
                                .frame(width: 22, height: 22)
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(section.title)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 2)
                    .tag(section)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 230)
        } detail: {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 24)
                    VStack(alignment: .leading, spacing: 20) {
                        selectedContent
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    Spacer(minLength: 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selectedSection?.title ?? "Settings")
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, idealWidth: 960, maxWidth: 1_100, minHeight: 600, idealHeight: 660, maxHeight: 760)
        .sheet(isPresented: $showingModelDownload, onDismiss: {
            Task { await refreshParakeetModelStatus() }
        }) {
            ModelDownloadView()
                .environmentObject(appModel)
        }
        .task {
            await refreshParakeetModelStatus()
            refreshPermissions()
        }
        .onDisappear {
            stopMicTest()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .microphoneTestLevelDidChange).receive(on: RunLoop.main)) { notification in
            guard let level = notification.userInfo?["level"] as? Float else { return }
            testAudioLevel = level
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if selectedSection == .privacy {
                refreshPermissions()
            }
        }
        .alert("Delete Parakeet Model?", isPresented: $showingModelDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await ModelStore.shared.removeParakeetModel()
                    await refreshParakeetModelStatus()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the local Parakeet model files (~480 MB). You can re-download them anytime.")
        }
        .alert("Delete All Dictation History?", isPresented: $showingHistoryDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
                history.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved transcript from this Mac.")
        }
        .alert("Delete All Reference Words?", isPresented: $showingDictionaryDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
                dictionary.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every word from your local reference library.")
        }
        .alert("VoiceFlow", isPresented: $appModel.showingError) {
            Button("OK") {
                appModel.dismissError()
            }
        } message: {
            Text(appModel.errorMessage ?? "An unexpected error occurred.")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection ?? .general {
        case .general: generalTab
        case .audio: audioTab
        case .transcription: transcriptionTab
        case .output: outputTab
        case .shortcuts: shortcutsTab
        case .dictionary: dictionaryTab
        case .history: historyTab
        case .privacy: privacyTab
        case .about: aboutTab
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Startup & HUD") {
                SettingToggleRow(
                    title: "Launch at Login",
                    subtitle: "Automatically start VoiceFlow in the menu bar when your Mac turns on",
                    isOn: $settings.launchAtLogin
                )
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }

                Divider()

                SettingToggleRow(
                    title: "Show Recording HUD",
                    subtitle: "Display floating audio wave bubble at center of screen during dictation",
                    isOn: $settings.showHUD
                )
            }

            SettingCard(title: "Recording Duration") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maximum Duration")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically stops dictation after this timeout")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(settings.maxRecordingDuration)) seconds")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(settings.accentColor.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(settings.accentColor.color.opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 12) {
                        Text("30s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.maxRecordingDuration, in: 30...300, step: 30)
                            .tint(settings.accentColor.color)
                        Text("5m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            SettingCard(title: "Appearance") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent Color")
                            .font(.system(size: 13, weight: .medium))
                        Text("Theme color for HUD elements, indicators, and badges")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.accentColor) {
                        ForEach(AppAccentColor.allCases) { accent in
                            HStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 10, height: 10)
                                Text(accent.rawValue)
                            }
                            .tag(accent)
                        }
                    }
                    .frame(width: 160)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Audio Tab
    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Microphone Input") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input Device")
                            .font(.system(size: 13, weight: .medium))
                        Text("Microphone used for speech capture")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.selectedAudioDeviceName) {
                        Text("System Default").tag("Default")
                        ForEach(AudioDeviceManager.shared.availableInputs, id: \.self) { device in
                            Text(device.name).tag(device.name)
                        }
                    }
                    .frame(width: 200)
                }
                .padding(.vertical, 2)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input Level Meter")
                                .font(.system(size: 13, weight: .medium))
                            Text(isTestingMic ? "Speak to test microphone response" : "Click Test Mic to check your microphone input")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isTestingMic ? "Stop Test" : "Test Mic") {
                            toggleMicTest()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appModel.isRecording || appModel.isProcessing)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: (isTestingMic ? testAudioLevel : appModel.audioLevel) > 0.75
                                            ? [.orange, .red]
                                            : [.teal, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(isTestingMic ? testAudioLevel : appModel.audioLevel))
                                .animation(.linear(duration: 0.05), value: isTestingMic ? testAudioLevel : appModel.audioLevel)
                        }
                    }
                    .frame(height: 10)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            SettingCard(title: "Audio Processing") {
                SettingToggleRow(
                    title: "Auto Punctuation",
                    subtitle: "Automatically inserts periods, commas, and questions based on cadence",
                    isOn: $settings.autoPunctuation
                )

                Divider()

                SettingToggleRow(
                    title: "Noise Reduction",
                    subtitle: "Filters out ambient room noises and keystrokes while speaking",
                    isOn: $settings.noiseReduction
                )

                Divider()

                SettingToggleRow(
                    title: "Voice Activity Detection",
                    subtitle: "Automatically pauses transcription when background silence is detected",
                    isOn: $settings.voiceActivityDetection
                )
            }
        }
    }

    // MARK: - Transcription Tab
    private var transcriptionTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Recognition Engine") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Primary Engine")
                                .font(.system(size: 13, weight: .medium))
                            Text("Default speech recognition provider")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.selectedEngine) {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Label(engine.rawValue, systemImage: engine.icon).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190)
                    }

                    Text(engineDescription(settings.selectedEngine))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fallback Engine")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically utilized if the primary engine encounters an error")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.fallbackEngine) {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Label(engine.rawValue, systemImage: engine.icon).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spoken Language")
                                .font(.system(size: 13, weight: .medium))
                            Text("Language model used for decoding speech")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.selectedLocale) {
                            ForEach(commonLocales, id: \.identifier) { locale in
                                Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                    .tag(locale)
                            }
                        }
                        .frame(width: 190)
                    }
                }
                .padding(.vertical, 4)
            }

            SettingCard(title: "Parakeet Local Model") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Parakeet TDT 0.6B v3")
                                .font(.system(size: 14, weight: .semibold))

                            if isParakeetModelInstalled {
                                Label("Installed", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.green.opacity(0.12), in: Capsule())
                            } else {
                                Text("Not Installed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text("NVIDIA Parakeet • 25 languages • ~480 MB local storage")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if isParakeetModelInstalled {
                            let size = ByteCountFormatter.string(fromByteCount: parakeetModelSize, countStyle: .file)
                            Text("Disk space: \(size)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if isParakeetModelInstalled {
                        Button(role: .destructive) {
                            showingModelDeleteConfirmation = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            showingModelDownload = true
                        } label: {
                            Label("Download Model", systemImage: "arrow.down.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Output Tab
    private var outputTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Text Insertion Method") {
                VStack(spacing: 10) {
                    OutputModeCard(
                        mode: .pasteAtCursor,
                        selectedMode: $settings.outputMode,
                        title: "Paste at Cursor (Recommended)",
                        subtitle: "Automatically types the transcribed text directly into whichever app you are actively typing in",
                        icon: "cursorarrow.rays"
                    )

                    OutputModeCard(
                        mode: .clipboardOnly,
                        selectedMode: $settings.outputMode,
                        title: "Copy to Clipboard",
                        subtitle: "Leaves the transcript on your clipboard so you can paste manually with ⌘V whenever you choose",
                        icon: "doc.on.clipboard"
                    )
                }
                .padding(.vertical, 4)
            }

            SettingCard(title: "Insertion Behavior") {
                SettingToggleRow(
                    title: "Restore clipboard after paste",
                    subtitle: "Safely restores whatever was on your clipboard before dictating after 0.5s",
                    isOn: $settings.restoreClipboard
                )

                Divider()

                SettingToggleRow(
                    title: "Auto-dismiss HUD after insert",
                    subtitle: "Instantly hides the floating recording bubble when text insertion completes",
                    isOn: $settings.autoDismissHUD
                )
            }
        }
    }

    // MARK: - Shortcuts Tab
    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Hotkey Setup") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Shortcut Mode", selection: Binding(
                        get: { settings.useDefaultHotkeys },
                        set: { newValue in
                            settings.useDefaultHotkeys = newValue
                            NotificationCenter.default.post(
                                name: Notification.Name.defaultHotkeysChanged,
                                object: newValue
                            )
                        }
                    )) {
                        Text("Recommended Defaults (Wispr Flow)").tag(true)
                        Text("Custom Recorded Hotkeys").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    
                    Text(settings.useDefaultHotkeys
                         ? "Using built-in dedicated hardware keys: Right Option for push-to-talk, and Right ⌘+⌥ for continuous recording."
                         : "Customize and record your own preferred key combinations. VoiceFlow reserves them in the background across all applications.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if settings.useDefaultHotkeys {
                SettingCard(title: "Built-in Wispr Flow Hotkeys") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            KeycapBadge(text: "⌥ Right Option")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Push-to-Talk (Hold & Speak)")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Hold anywhere to dictate. As soon as you release, VoiceFlow types at your cursor.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack(spacing: 12) {
                            KeycapBadge(text: "⌘ + ⌥ Right Cmd+Opt")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Continuous Hands-Free Mode")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Press once to start continuous recording; remove fingers; press again to finish and auto-type.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack(spacing: 12) {
                            KeycapBadge(text: "Esc")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Instant Cancel")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Cancel recording immediately without typing anything.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Want to choose your own keys?")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Record Custom Hotkeys…") {
                                settings.useDefaultHotkeys = false
                                NotificationCenter.default.post(
                                    name: Notification.Name.defaultHotkeysChanged,
                                    object: false
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(settings.accentColor.color)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                // Custom Push-to-Talk Card
                SettingCard(title: "Custom Push-to-Talk Hotkey") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold to Speak")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Hold this key combination to record, release to stop and auto-type")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .startDictation) { _ in
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Quick Presets:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            PresetButton(title: "⌥ Space") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.space, modifiers: [.option]), for: .startDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            PresetButton(title: "⌃ Space") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.space, modifiers: [.control]), for: .startDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            PresetButton(title: "⌥ D") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.d, modifiers: [.option]), for: .startDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            PresetButton(title: "F5") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.f5), for: .startDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            Spacer()
                            
                            Button("Reset") {
                                KeyboardShortcuts.reset(.startDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Custom Continuous Toggle Card
                SettingCard(title: "Custom Continuous Mode Hotkey") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Toggle Hands-Free Recording")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Press once to start hands-free recording; press again to finish and type")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .toggleDictation) { _ in
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Quick Presets:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            PresetButton(title: "⌥⌘ Space") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .option]), for: .toggleDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            PresetButton(title: "⌃⌥ D") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option]), for: .toggleDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            PresetButton(title: "⇧⌘ Space") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.space, modifiers: [.shift, .command]), for: .toggleDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            
                            Spacer()
                            
                            Button("Reset") {
                                KeyboardShortcuts.reset(.toggleDictation)
                                HotkeyService.shared.retryMonitoringIfReady()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Cancel & Tips Card
                SettingCard(title: "Recording Instructions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            KeycapBadge(text: "Esc")
                            Text("Press Escape anytime to cancel dictation without typing.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(settings.accentColor.color)
                                .font(.system(size: 14))
                            Text("Click any recorder box above and press your desired key combination on your keyboard (e.g. ⌥Space, ⌃Space, or F5). Release to save. VoiceFlow automatically reserves it in the background.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Dictionary Tab
    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Custom Dictionary") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reference words")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add names, acronyms, products, and other terms you use often. VoiceFlow keeps their spelling and capitalization when they appear in a transcription. All entries stay on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("Add a reference word or phrase", text: $dictionaryWord)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            dictionary.add(word: dictionaryWord)
                            dictionaryWord = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColor.color)
                        .disabled(dictionaryWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            }

            if dictionary.entries.isEmpty {
                ContentUnavailableView(
                    "No Reference Words",
                    systemImage: "text.book.closed",
                    description: Text("Add terms such as “Parakeet”, “VoiceFlow”, or your name.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                SettingCard(title: "Your Reference Library") {
                    VStack(spacing: 0) {
                        ForEach(dictionary.entries) { entry in
                            HStack(spacing: 10) {
                                Text(entry.word)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Button {
                                    dictionary.delete(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .help("Delete this correction")
                            }
                            .padding(.vertical, 10)

                            if entry.id != dictionary.entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Delete All Reference Words", role: .destructive) {
                    showingDictionaryDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(dictionary.entries.isEmpty)
            }
        }
    }

    // MARK: - History Tab
    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Dictation History") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Saved locally on this Mac")
                            .font(.system(size: 13, weight: .medium))
                        Text("Each completed dictation is saved with its date and time.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete All", role: .destructive) {
                        showingHistoryDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(history.entries.isEmpty)
                }
                .padding(.vertical, 4)
            }

            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No Dictation History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed dictations will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                SettingCard(title: "Recent Dictations") {
                    VStack(spacing: 0) {
                        ForEach(history.entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.transcript)
                                        .font(.system(size: 13))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    history.delete(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .help("Delete this dictation")
                            }
                            .padding(.vertical, 10)

                            if entry.id != history.entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Privacy Tab
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Privacy Commitment") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                        Text("100% Local & Private Speech Processing")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text("• No voice audio or transcripts ever leave your Mac")
                    Text("• Zero telemetry, analytics, or background tracking")
                    Text("• Models run exclusively via Apple Silicon Neural Engine and CPU")
                    Text("• No accounts, logins, or cloud subscriptions required")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }

            SettingCard(title: "macOS System Permissions") {
                VStack(spacing: 12) {
                    ModernPermissionRow(
                        title: "Microphone Access",
                        description: "Required to capture spoken words for transcription",
                        isGranted: micGranted,
                        action: {
                            refreshPermissions()
                            guard !PermissionService.shared.checkMicrophonePermission() else { return }
                            Task {
                                let granted = await PermissionService.shared.requestMicrophonePermission()
                                if !granted {
                                    PermissionService.shared.openMicrophoneSettings()
                                }
                                refreshPermissions()
                            }
                        }
                    )

                    Divider()

                    ModernPermissionRow(
                        title: "Accessibility Access",
                        description: "Required to simulate Command+V to paste at the cursor into other apps",
                        isGranted: axGranted,
                        action: {
                            refreshPermissions()
                            guard !PermissionService.shared.checkAccessibilityPermission() else { return }
                            PermissionService.shared.requestAccessibilityPermission()
                            PermissionService.shared.openAccessibilitySettings()
                            refreshPermissions()
                        }
                    )

                    Divider()

                    ModernPermissionRow(
                        title: "Speech Recognition Access",
                        description: "Required for Apple Speech on-device transcription",
                        isGranted: speechGranted,
                        action: {
                            refreshPermissions()
                            guard !PermissionService.shared.checkSpeechRecognitionPermission() else { return }
                            Task {
                                let granted = await PermissionService.shared.requestSpeechRecognitionPermission()
                                if !granted {
                                    PermissionService.shared.openSpeechRecognitionSettings()
                                }
                                refreshPermissions()
                            }
                        }
                    )

                    Divider()

                    HStack {
                        Spacer()
                        Button {
                            refreshPermissions()
                        } label: {
                            Label("Re-check Permissions", systemImage: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "") {
                VStack(spacing: 14) {
                    AppIconView(size: 72)
                    
                    VStack(spacing: 4) {
                        Text("VoiceFlow")
                            .font(.system(size: 22, weight: .bold))
                        Text("Version 1.0.0 (Build 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("Fast, private, push-to-talk speech dictation for macOS.\nPowered by Apple Speech Framework & NVIDIA Parakeet.")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    VStack(spacing: 3) {
                        Text("Created by")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Siva Saikumar Reddy K")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            SettingCard(title: "Open Source Credits") {
                VStack(spacing: 10) {
                    LinkRow(title: "Apple Speech Framework", url: "https://developer.apple.com/documentation/speech")
                    Divider()
                    LinkRow(title: "FluidAudio & Parakeet by NVIDIA", url: "https://github.com/FluidInference/FluidAudio")
                    Divider()
                    LinkRow(title: "KeyboardShortcuts by Sindre Sorhus", url: "https://github.com/sindresorhus/KeyboardShortcuts")
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Helpers
    private func engineDescription(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .apple:
            return "Apple Speech: Native macOS on-device speech engine. Lightning fast, zero setup, private."
        case .parakeet:
            return "Parakeet TDT 0.6B: High-accuracy multilingual model by NVIDIA. 25 languages support (~480 MB)."
        }
    }

    private let commonLocales: [Locale] = [
        Locale(identifier: "en_US"),
        Locale(identifier: "en_GB"),
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    private func refreshParakeetModelStatus() async {
        isParakeetModelInstalled = await ModelStore.shared.isParakeetModelInstalled()
        parakeetModelSize = await ModelStore.shared.getModelSize()
    }

    private func refreshPermissions() {
        micGranted = PermissionService.shared.checkMicrophonePermission()
        axGranted = PermissionService.shared.checkAccessibilityPermission()
        speechGranted = PermissionService.shared.checkSpeechRecognitionPermission()
        if axGranted {
            HotkeyService.shared.retryMonitoringIfReady()
        }
        Task {
            await appModel.refreshPermissions()
        }
    }

    private func toggleMicTest() {
        if isTestingMic {
            stopMicTest()
        } else {
            startMicTest()
        }
    }

    private func startMicTest() {
        guard !appModel.isRecording, !appModel.isProcessing else { return }
        guard micGranted else {
            appModel.showError("Microphone access is required to test the input level. Enable it in System Settings, then try again.")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            appModel.showError("No usable microphone input is available. Check the selected input in System Settings.")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            let level = min(max(rms * 10, 0), 1)
            NotificationCenter.default.post(
                name: .microphoneTestLevelDidChange,
                object: nil,
                userInfo: ["level": level]
            )
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            appModel.showError("Microphone test could not start: \(error.localizedDescription)")
            return
        }
        self.testEngine = engine
        self.isTestingMic = true
    }

    private func stopMicTest() {
        testEngine?.stop()
        testEngine?.inputNode.removeTap(onBus: 0)
        testEngine = nil
        testAudioLevel = 0.0
        isTestingMic = false
    }
}

extension Notification.Name {
    static let microphoneTestLevelDidChange = Notification.Name("VoiceFlowApp.microphoneTestLevelDidChange")
}

// MARK: - Modern UI Component Helpers

struct SettingCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.8)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct OutputModeCard: View {
    let mode: OutputMode
    @Binding var selectedMode: OutputMode
    let title: String
    let subtitle: String
    let icon: String

    var isSelected: Bool { selectedMode == mode }

    var body: some View {
        Button {
            selectedMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct KeycapBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.8)
            )
    }
}

struct PresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help("Click to quickly assign \(title) as your shortcut")
    }
}

struct ModernPermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))

                    Label(isGranted ? "Granted" : "Not Granted", systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isGranted ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isGranted ? Color.green : Color.red).opacity(0.12), in: Capsule())
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isGranted ? "Settings…" : "Grant Access", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

struct LinkRow: View {
    let title: String
    let url: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Link(destination: URL(string: url)!) {
                HStack(spacing: 4) {
                    Text("Visit")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11))
            }
        }
        .padding(.vertical, 2)
    }
}

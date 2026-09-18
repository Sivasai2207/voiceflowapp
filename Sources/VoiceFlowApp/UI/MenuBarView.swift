import SwiftUI
import KeyboardShortcuts

@available(macOS 14.0, *)
struct MenuBarView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject private var settings = SettingsStore.shared
    var openSettings: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            
            actionButtonView
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            
            quickControlsView
                .padding(.horizontal, 14)
            
            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            
            footerView
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.96))
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            AppIconView(size: 28, showShadow: false)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("VoiceFlow")
                    .font(.system(size: 14, weight: .bold))
                
                Text(appModel.isRecording ? "Recording speech…" : appModel.isProcessing ? "Transcribing & Polishing…" : "Active in Background")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appModel.isRecording ? .red : appModel.isProcessing ? .orange : .green)
            }
            
            Spacer()
            
            if appModel.isRecording {
                RecordingIndicatorView()
            } else {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.6), radius: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
    
    // MARK: - Background Hotkey Reservation Card
    private var actionButtonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appModel.isRecording {
                Button {
                    appModel.toggleRecording()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Stop & Type Now")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Release key to stop")
                            .font(.system(size: 11))
                            .opacity(0.85)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(settings.accentColor.color)
                        
                        Text("Hotkey Reserved in Background")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        KeycapBadge(text: settings.useDefaultHotkeys ? "⌥ Right Opt" : "Custom")
                    }
                    
                    Text("Hold the hotkey anywhere on your Mac to speak. When you release, VoiceFlow automatically types into whichever app you pointed at.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                    
                    HStack {
                        Spacer()
                        Button {
                            appModel.toggleRecording()
                        } label: {
                            Label("Manual Click Start", systemImage: "mic.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(settings.accentColor.color)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(settings.accentColor.color.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Quick Controls
    private var quickControlsView: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Engine", systemImage: "cpu")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Picker("", selection: $settings.selectedEngine) {
                    ForEach(TranscriptionEngine.allCases) { engine in
                        Label(engine.rawValue, systemImage: engine.icon)
                            .tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 155)
                .disabled(appModel.isRecording || appModel.isProcessing)
                .onChange(of: settings.selectedEngine) { _, newEngine in
                    appModel.selectedEngine = newEngine
                }
            }
            
            HStack {
                Label("Output", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Picker("", selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 155)
                .disabled(appModel.isRecording || appModel.isProcessing)
                .onChange(of: settings.outputMode) { _, newMode in
                    appModel.outputMode = newMode
                }
            }
        }
    }
    
    // MARK: - Last Transcript
    private var lastTranscriptView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last Transcript")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: { appModel.copyLastTranscript() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(settings.accentColor.color)
                }
                .buttonStyle(.plain)
            }
            
            Text(appModel.lastTranscript)
                .font(.system(size: 12))
                .lineLimit(3)
                .truncationMode(.tail)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 16) {
            Button(action: {
                if let open = openSettings {
                    open()
                } else {
                    AppDelegate.shared?.showSettings()
                }
            }) {
                Label("Settings…", systemImage: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            
            Spacer()
            
            Button(action: { NSApp.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct RecordingIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .scaleEffect(isAnimating ? 1.2 : 0.8)
                .opacity(isAnimating ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            
            Text("REC")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.red.opacity(0.12), in: Capsule())
        .onAppear { isAnimating = true }
    }
}

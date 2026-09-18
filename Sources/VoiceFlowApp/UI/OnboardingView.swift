import SwiftUI

@available(macOS 14.0, *)
struct OnboardingView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var currentStep = 0
    @State private var microphonePermissionGranted = false
    @State private var accessibilityPermissionGranted = false
    
    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to VoiceFlow",
            subtitle: "Push-to-talk dictation that works everywhere",
            icon: "waveform.circle.fill",
            description: "Hold a key, speak naturally, release to transcribe. Your words appear instantly at your cursor."
        ),
        OnboardingStep(
            title: "Microphone Access",
            subtitle: "Required for voice recording",
            icon: "mic.fill",
            description: "VoiceFlow needs microphone access to capture your speech. All processing happens locally on your Mac."
        ),
        OnboardingStep(
            title: "Accessibility Access",
            subtitle: "Required for cross-app text insertion",
            icon: "hand.tap.fill",
            description: "To automatically paste text into any app, VoiceFlow needs accessibility permission. You can also use clipboard-only mode."
        ),
        OnboardingStep(
            title: "Choose Your Shortcut",
            subtitle: "Right Option by default",
            icon: "keyboard.fill",
            description: "Hold Right Option to record, release to transcribe. You can customize this in Settings anytime."
        ),
        OnboardingStep(
            title: "Select Engine",
            subtitle: "Apple Speech (primary) + Parakeet (fallback)",
            icon: "cpu.fill",
            description: "Apple's on-device recognition is fast and private. Parakeet provides 25-language support as a local fallback."
        ),
        OnboardingStep(
            title: "You're Ready!",
            subtitle: "Start dictating in any app",
            icon: "checkmark.circle.fill",
            description: "Hold Right Option and speak. Your words will appear at your cursor. Press Escape to cancel anytime."
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentStep) {
                ForEach(0..<steps.count, id: \.self) { index in
                    OnboardingStepView(step: steps[index], isActive: index == currentStep)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < steps.count - 1 {
                    Button("Next") {
                        handleNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 600, height: 520)
        .background(.regularMaterial)
    }
    
    private func handleNext() {
        switch currentStep {
        case 1:
            requestMicrophonePermission()
        case 2:
            requestAccessibilityPermission()
        default:
            withAnimation { currentStep += 1 }
        }
    }
    
    private func requestMicrophonePermission() {
        Task {
            let granted = await PermissionService.shared.requestMicrophonePermission()
            await MainActor.run {
                microphonePermissionGranted = granted
                withAnimation { currentStep += 1 }
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        PermissionService.shared.requestAccessibilityPermission()

        Task { @MainActor in
            while !Task.isCancelled {
                if PermissionService.shared.checkAccessibilityPermission() {
                    accessibilityPermissionGranted = true
                    withAnimation { currentStep += 1 }
                    return
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    
    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

struct OnboardingStep {
    let title: String
    let subtitle: String
    let icon: String
    let description: String
}

struct OnboardingStepView: View {
    let step: OnboardingStep
    let isActive: Bool
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            if step.icon == "waveform.circle.fill" {
                AppIconView(size: 84)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            } else {
                Image(systemName: step.icon)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                    .symbolEffect(.pulse, options: .repeating, value: isActive)
            }
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text(step.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Text(step.description)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index <= Int(Float(6) * (Float(index) / 5.0)) ? .teal : .secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.1), value: isActive)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }
}

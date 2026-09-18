import SwiftUI

@available(macOS 14.0, *)
struct RecordingHUD: View {
    @EnvironmentObject var appModel: AppModel
    @State private var animationPhase = 0.0
    @State private var waveOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 16) {
                engineIndicator
                
                if appModel.isRecording {
                    waveformView
                } else if appModel.isProcessing {
                    processingView
                }
                
                transcriptView
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(width: 360, height: 180)
        .onAppear {
            startAnimations()
        }
        .onChange(of: appModel.isRecording) { _, newValue in
            if newValue {
                startAnimations()
            }
        }
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor).opacity(0.95),
                        Color(NSColor.controlBackgroundColor).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.teal.opacity(0.4), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            )
    }
    
    private var engineIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appModel.isRecording ? .red : appModel.isProcessing ? .orange : .teal)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseScale)
                .animation(
                    appModel.isRecording || appModel.isProcessing
                        ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                        : .default,
                    value: pulseScale
                )
            
            Text(appModel.isRecording ? "Listening" : appModel.isProcessing ? "Processing" : "Ready")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if appModel.isRecording {
                Text(formatDuration(appModel.recordingDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.teal)
                    .contentTransition(.numericText())
            }
            
            Image(systemName: appModel.selectedEngine.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.teal)
        }
    }
    
    private var waveformView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let barCount = 40
            let barWidth = width / CGFloat(barCount * 2)
            let maxHeight = height * 0.7
            
            ZStack {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = index < appModel.audioLevels.count 
                        ? appModel.audioLevels[index] 
                        : Float.random(in: 0.05...0.2)
                    let barHeight = CGFloat(level) * maxHeight
                    let x = CGFloat(index) * (barWidth * 2) + barWidth / 2
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(
                            LinearGradient(
                                colors: waveColors(for: level),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: max(barHeight, 3))
                        .position(x: x, y: height / 2)
                        .animation(
                            .spring(response: 0.15, dampingFraction: 0.7)
                                .delay(Double(index) * 0.01),
                            value: level
                        )
                }
            }
        }
        .frame(height: 60)
    }
    
    private var processingView: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: pulseScale
                    )
            }
        }
        .frame(height: 60)
    }
    
    private var transcriptView: some View {
        Group {
            if !appModel.currentTranscript.isEmpty {
                ScrollView {
                    Text(appModel.currentTranscript)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 8)
                }
                .frame(maxHeight: 60)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appModel.currentTranscript)
    }
    
    private func waveColors(for level: Float) -> [Color] {
        let intensity = CGFloat(level)
        return [
            Color(red: 0.0, green: 0.7, blue: 0.85).opacity(0.6 + intensity * 0.4),
            Color(red: 0.0, green: 0.5, blue: 0.9).opacity(0.7 + intensity * 0.3),
            Color(red: 0.2, green: 0.3, blue: 1.0).opacity(0.8 + intensity * 0.2)
        ]
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
    
    private func startAnimations() {
        pulseScale = 1.1
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            animationPhase += 2 * .pi
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

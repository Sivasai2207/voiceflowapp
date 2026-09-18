import SwiftUI
import Combine

@available(macOS 14.0, *)
struct WisprFlowHUD: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject private var settings = SettingsStore.shared
    
    @State private var phase: Double = 0
    @State private var waveAnimationTimer: AnyCancellable?
    @State private var smoothedLevel: Float = 0.05
    @State private var isHoveringStop = false
    
    // Gradient definitions matching Dribbble fluid wave
    private let cyanBlue = Color(red: 0.0, green: 0.85, blue: 1.0)
    private let magentaPink = Color(red: 1.0, green: 0.2, blue: 0.75)
    private let sunsetOrange = Color(red: 1.0, green: 0.55, blue: 0.15)
    private let electricPurple = Color(red: 0.65, green: 0.35, blue: 1.0)
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Status / Mic Icon
            leftStatusView
            
            // Center: Fluid Luminous Waveform (Dribbble animation style)
            ZStack {
                if appModel.isProcessing {
                    processingWaveView
                } else {
                    fluidHarmonicWaveView
                }
            }
            .frame(width: 150, height: 38)
            .clipped()
            
            // Right: Duration or Status Text
            rightStatusView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 290, height: 58)
        .background(
            // Dark glassmorphic floating pill matching Wispr Flow
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.85))
                
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.5))
                
                // Subtle glowing rim
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                cyanBlue.opacity(0.3),
                                magentaPink.opacity(0.2),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
        .shadow(color: cyanBlue.opacity(0.15), radius: 12, x: 0, y: 2)
        .onAppear {
            startWaveAnimation()
        }
        .onDisappear {
            stopWaveAnimation()
        }
        .onChange(of: appModel.audioLevel) { _, newLevel in
            // Smooth audio level for organic fluid response
            withAnimation(.easeOut(duration: 0.08)) {
                smoothedLevel = max(0.08, min(1.0, smoothedLevel * 0.4 + newLevel * 0.6))
            }
        }
    }
    
    // MARK: - Left Status / Stop Button
    private var leftStatusView: some View {
        HStack(spacing: 8) {
            if appModel.isRecording {
                Button {
                    print("🛑 User clicked Red Stop button on blob")
                    appModel.stopRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(isHoveringStop ? 0.35 : 0.2))
                            .frame(width: 22, height: 22)
                        
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .shadow(color: Color.red.opacity(0.85), radius: 5)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 5.5, height: 5.5)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringStop = hovering
                }
                .help("Click to stop dictation and type text")
            } else {
                Circle()
                    .fill(appModel.isProcessing ? sunsetOrange : cyanBlue)
                    .frame(width: 8, height: 8)
                    .shadow(color: (appModel.isProcessing ? sunsetOrange : cyanBlue).opacity(0.8), radius: 4)
            }
            
            AppLogoMarkView(size: 14)
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
    
    // MARK: - Right Status & Timer
    private var rightStatusView: some View {
        Group {
            if appModel.isRecording {
                Button {
                    print("🛑 User clicked Right Stop/Timer on blob")
                    appModel.stopRecording()
                } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatDuration(appModel.recordingDuration))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 6))
                            Text(appModel.isContinuousRecording ? "HANDS-FREE" : "STOP")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(appModel.isContinuousRecording ? cyanBlue : Color.red)
                    }
                }
                .buttonStyle(.plain)
                .help(appModel.isContinuousRecording ? "Click to stop hands-free dictation and type text" : "Click to stop dictation and type text")
            } else if appModel.isProcessing {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Typing…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sunsetOrange)
                    Text("Polishing")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 46, alignment: .trailing)
    }
    
    // MARK: - Fluid Harmonic Waveform (Dribbble Style)
    private var fluidHarmonicWaveView: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h / 2
            let amp = CGFloat(smoothedLevel) * (h * 0.42) + 3.0
            
            // Draw 4 overlapping harmonic ribbon layers with additive luminous blending
            
            // Layer 1: Electric Blue / Cyan harmonic wave (wide, deep)
            let path1 = createHarmonicPath(
                width: w,
                midY: midY,
                amplitude: amp * 1.0,
                frequency: 2.2,
                phase: phase,
                secondaryAmp: amp * 0.4,
                secondaryFreq: 4.5
            )
            context.stroke(
                path1,
                with: .linearGradient(
                    Gradient(colors: [cyanBlue.opacity(0.1), cyanBlue, electricPurple, cyanBlue.opacity(0.1)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: w, y: midY)
                ),
                lineWidth: 2.5
            )
            
            // Layer 2: Vibrant Magenta / Pink harmonic wave (offset phase, counter-flow)
            let path2 = createHarmonicPath(
                width: w,
                midY: midY,
                amplitude: amp * 0.85,
                frequency: 2.6,
                phase: -phase * 1.2 + .pi * 0.5,
                secondaryAmp: amp * 0.35,
                secondaryFreq: 5.2
            )
            context.stroke(
                path2,
                with: .linearGradient(
                    Gradient(colors: [magentaPink.opacity(0.1), magentaPink, sunsetOrange, magentaPink.opacity(0.1)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: w, y: midY)
                ),
                lineWidth: 2.2
            )
            
            // Layer 3: Sunset Orange / Amber undertone wave
            let path3 = createHarmonicPath(
                width: w,
                midY: midY,
                amplitude: amp * 0.65,
                frequency: 1.8,
                phase: phase * 0.8 + .pi,
                secondaryAmp: amp * 0.25,
                secondaryFreq: 3.6
            )
            context.stroke(
                path3,
                with: .linearGradient(
                    Gradient(colors: [sunsetOrange.opacity(0.0), sunsetOrange, magentaPink, sunsetOrange.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: w, y: midY)
                ),
                lineWidth: 1.8
            )
            
            // Layer 4: Intense Core Silk Ribbon (Center luminous highlight)
            let path4 = createHarmonicPath(
                width: w,
                midY: midY,
                amplitude: amp * 0.5,
                frequency: 3.0,
                phase: phase * 1.5,
                secondaryAmp: amp * 0.2,
                secondaryFreq: 6.0
            )
            context.stroke(
                path4,
                with: .color(Color.white.opacity(0.95)),
                lineWidth: 1.2
            )
        }
        .drawingGroup() // Metal hardware acceleration on Apple Silicon
    }
    
    // MARK: - Processing State View (Converging Luminous Energy)
    private var processingWaveView: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { i in
                let waveOffset = Double(i) * 0.3
                let pulse = abs(sin(phase * 3 + waveOffset))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [cyanBlue, magentaPink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: CGFloat(8 + pulse * 18))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }
    
    // Helper to generate fluid multi-frequency wave curve
    private func createHarmonicPath(
        width: CGFloat,
        midY: CGFloat,
        amplitude: CGFloat,
        frequency: Double,
        phase: Double,
        secondaryAmp: CGFloat,
        secondaryFreq: Double
    ) -> Path {
        var path = Path()
        let steps = 60
        let stepWidth = width / CGFloat(steps)
        
        for i in 0...steps {
            let x = CGFloat(i) * stepWidth
            let normX = Double(i) / Double(steps) // 0.0 to 1.0
            
            // Taper wave towards the left and right edges so it meets the horizontal axis smoothly
            let envelope = sin(normX * .pi)
            
            let wave1 = sin(normX * .pi * 2 * frequency + phase) * Double(amplitude)
            let wave2 = sin(normX * .pi * 2 * secondaryFreq - phase * 0.7) * Double(secondaryAmp)
            let y = midY + CGFloat((wave1 + wave2) * envelope)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func startWaveAnimation() {
        waveAnimationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let speed = 0.04 + Double(smoothedLevel) * 0.08
                phase += speed
                if phase > .pi * 200 {
                    phase = 0
                }
            }
    }
    
    private func stopWaveAnimation() {
        waveAnimationTimer?.cancel()
        waveAnimationTimer = nil
    }
}

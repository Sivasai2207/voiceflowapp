import SwiftUI
import Combine

@available(macOS 14.0, *)
struct RecordingBubbleHUD: View {
    @EnvironmentObject var appModel: AppModel
    @State private var animationPhase: Double = 0
    @State private var wavePhases: [Double] = Array(repeating: 0, count: 6)
    @State private var orbScale: CGFloat = 1.0
    @State private var orbGlow: Double = 0
    @State private var isAnimating = false
    @State private var displayText = "Listening..."
    @State private var waveformData: [CGFloat] = Array(repeating: 0.1, count: 64)
    
    private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    private let textTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    
    private let listeningTexts = ["Listening...", "Speak now...", "I'm listening", "Go ahead..."]
    private let processingTexts = ["Processing...", "Transcribing...", "Almost there..."]
    private let textColors = [
        Color(red: 0.4, green: 0.8, blue: 1.0),
        Color(red: 0.6, green: 0.4, blue: 1.0),
        Color(red: 1.0, green: 0.4, blue: 0.8),
        Color(red: 0.3, green: 1.0, blue: 0.6)
    ]
    
    var body: some View {
        ZStack {
            // Background blur/dimming
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    appModel.cancelRecording()
                }
            
            VStack {
                Spacer()
                
                // Main orb with waves
                ZStack {
                    // Outer expanding rings
                    ForEach(0..<6, id: \.self) { index in
                        OuterWaveRing(
                            index: index,
                            phase: wavePhases[index],
                            audioLevel: appModel.audioLevel,
                            isRecording: appModel.isRecording,
                            colors: textColors
                        )
                    }
                    
                    // Middle rings
                    ForEach(0..<4, id: \.self) { index in
                        MiddleWaveRing(
                            index: index,
                            phase: wavePhases[index + 2],
                            audioLevel: appModel.audioLevel,
                            isRecording: appModel.isRecording,
                            colors: textColors
                        )
                    }
                    
                    // Main glowing orb
                    GlowingOrb(
                        scale: orbScale,
                        glow: orbGlow,
                        audioLevel: appModel.audioLevel,
                        isRecording: appModel.isRecording,
                        isProcessing: appModel.isProcessing,
                        colors: textColors
                    )
                    
                    // Center icon
                    CenterWaveform(
                        audioLevel: appModel.audioLevel,
                        isRecording: appModel.isRecording,
                        isProcessing: appModel.isProcessing
                    )
                }
                .frame(width: 280, height: 280)
                
                // Status text
                VStack(spacing: 8) {
                    Text(displayText)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: displayText)
                    
                    // Live waveform mini-bar
                    if appModel.isRecording {
                        MiniWaveformView(levels: appModel.audioLevels)
                            .frame(width: 180, height: 24)
                            .padding(.top, 4)
                    }
                    
                    // Duration
                    if appModel.isRecording {
                        Text(formatDuration(appModel.recordingDuration))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 20)
                
                // Hint
                Text(hintText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                
                Spacer().frame(height: 100)
            }
        }
        .onReceive(timer) { _ in
            updateAnimations()
        }
        .onReceive(textTimer) { _ in
            updateText()
        }
        .onChange(of: appModel.isRecording) { _, newValue in
            isAnimating = newValue
            if newValue {
                startAnimations()
            } else {
                stopAnimations()
            }
        }
        .onChange(of: appModel.isProcessing) { _, newValue in
            if newValue {
                displayText = processingTexts.randomElement() ?? "Processing..."
            }
        }
        .onAppear {
            if appModel.isRecording {
                startAnimations()
            }
        }
    }
    
    private var hintText: String {
        if appModel.isProcessing {
            return ""
        } else if appModel.isRecording {
            let settings = SettingsStore.shared
            if settings.hotkeyMode == .continuous {
                return "Press Right ⌘+⌥ or your toggle key to stop"
            } else {
                return "Release Right Option or your hotkey to finish"
            }
        }
        return ""
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func startAnimations() {
        isAnimating = true
        withAnimation(.easeInOut(duration: 0.5)) {
            orbScale = 1.05
            orbGlow = 1.0
        }
    }
    
    private func stopAnimations() {
        isAnimating = false
        withAnimation(.easeOut(duration: 0.8)) {
            orbScale = 0.8
            orbGlow = 0
        }
        // Reset wave phases
        wavePhases = Array(repeating: 0, count: 6)
    }
    
    private func updateAnimations() {
        guard isAnimating || appModel.isProcessing else { return }
        
        let baseSpeed = appModel.isRecording ? (0.02 + Double(appModel.audioLevel) * 0.04) : 0.015
        
        for i in 0..<wavePhases.count {
            let speed = baseSpeed * (1.0 + Double(i) * 0.15)
            wavePhases[i] += speed
            if wavePhases[i] > .pi * 2 {
                wavePhases[i] -= .pi * 2
            }
        }
        
        // Orb breathing
        let breathPhase = animationPhase * 2
        let audioLevelD = Double(appModel.audioLevel)
        orbScale = 1.0 + sin(breathPhase) * 0.03 + audioLevelD * 0.08
        orbGlow = 0.7 + sin(breathPhase * 1.5) * 0.2 + audioLevelD * 0.3
        
        animationPhase += 0.015
    }
    
    private func updateText() {
        if appModel.isRecording {
            displayText = listeningTexts.randomElement() ?? "Listening..."
        }
    }
}

// MARK: - Outer Wave Ring

struct OuterWaveRing: View {
    let index: Int
    let phase: Double
    let audioLevel: Float
    let isRecording: Bool
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let baseRadius = size * 0.35
            let maxExpansion = size * 0.4
            
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: colors),
                                center: .center,
                                startAngle: .degrees(phase * 180 / .pi + Double(ring) * 120),
                                endAngle: .degrees(phase * 180 / .pi + Double(ring) * 120 + 180)
                            ),
                            style: StrokeStyle(lineWidth: isRecording ? 2.5 : 1.5, lineCap: .round, dash: [20, 15], dashPhase: CGFloat(phase * 50))
                        )
                        .frame(
                            width: baseRadius * 2 + CGFloat(ring) * 30 + CGFloat(audioLevel) * maxExpansion,
                            height: baseRadius * 2 + CGFloat(ring) * 30 + CGFloat(audioLevel) * maxExpansion
                        )
                        .opacity(isRecording ? 0.6 - Double(ring) * 0.15 : 0.3 - Double(ring) * 0.1)
                        .blur(radius: isRecording ? 8 : 4)
                        .animation(
                            .linear(duration: 20.0 / Double(index + 1))
                            .repeatForever(autoreverses: false),
                            value: phase
                        )
                }
            }
        }
    }
}

// MARK: - Middle Wave Ring

struct MiddleWaveRing: View {
    let index: Int
    let phase: Double
    let audioLevel: Float
    let isRecording: Bool
    let colors: [Color]
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let baseRadius = size * 0.22
            
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    WavePath(
                        phase: phase + Double(ring) * .pi,
                        amplitude: isRecording ? (CGFloat(audioLevel) * 12 + 6) : 4,
                        frequency: 1.5 + Double(index) * 0.3,
                        baseRadius: baseRadius + CGFloat(ring) * 18
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                colors[(index + ring) % colors.count].opacity(isRecording ? 0.8 : 0.4),
                                colors[(index + ring + 1) % colors.count].opacity(isRecording ? 0.5 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: isRecording ? 3 : 2, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(
                        color: colors[(index + ring) % colors.count].opacity(isRecording ? 0.5 : 0.2),
                        radius: isRecording ? 12 : 6
                    )
                }
            }
        }
    }
}

// MARK: - Wave Path Shape

struct WavePath: Shape {
    let phase: Double
    let amplitude: CGFloat
    let frequency: Double
    let baseRadius: CGFloat
    
    var animatableData: Double {
        get { phase }
        set { }
    }
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let points = 120
        
        for i in 0..<points {
            let angle = Double(i) / Double(points) * .pi * 2
            let wave = sin(angle * frequency + phase) * amplitude
            let radius = baseRadius + wave
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Glowing Orb

struct GlowingOrb: View {
    let scale: CGFloat
    let glow: Double
    let audioLevel: Float
    let isRecording: Bool
    let isProcessing: Bool
    let colors: [Color]
    @State private var rotation: Double = 0
    
    var body: some View {
        let baseSize: CGFloat = 120
        
        ZStack {
            // Outer glow layers
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                colors[(i + 1) % colors.count].opacity(0.15 * Double(5 - i) * glow),
                                colors[i % colors.count].opacity(0.08 * Double(5 - i) * glow),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: baseSize * 0.8 + CGFloat(i) * 15
                        )
                    )
                    .frame(width: baseSize * 2 + CGFloat(i) * 40, height: baseSize * 2 + CGFloat(i) * 40)
                    .blur(radius: CGFloat(20 + i * 10) * CGFloat(glow))
                    .scaleEffect(1.0 + CGFloat(glow) * 0.15)
            }
            
            // Main orb body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isProcessing ? 0.3 : (isRecording ? 0.9 : 0.6)),
                            colors[0].opacity(isProcessing ? 0.5 : (isRecording ? 0.7 : 0.4)),
                            colors[1].opacity(isProcessing ? 0.3 : (isRecording ? 0.5 : 0.3)),
                            Color.black.opacity(0.1)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: baseSize
                    )
                )
                .frame(width: baseSize * 2, height: baseSize * 2)
                .shadow(color: colors[0].opacity(0.6), radius: 30, x: 0, y: 10)
                .shadow(color: colors[1].opacity(0.4), radius: 60, x: 0, y: 20)
            
            // Inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.25, y: 0.25),
                        startRadius: 0,
                        endRadius: baseSize * 0.6
                    )
                )
                .frame(width: baseSize * 1.8, height: baseSize * 1.8)
                .blur(radius: 2)
            
            // Rotating gradient border
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [colors[0], colors[1], colors[2], colors[3], colors[0]]),
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: 2.5
                )
                .frame(width: baseSize * 2 + 4, height: baseSize * 2 + 4)
                .blur(radius: 1)
            
            // Pulse ring when recording
            if isRecording {
                PulsingRing(audioLevel: audioLevel)
                    .frame(width: 160, height: 160)
            }
        }
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Pulsing Ring

struct PulsingRing: View {
    let audioLevel: Float
    @State private var pulsePhase: Double = 0
    
    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0),
                        Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.6),
                        Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4),
                        Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [30, 20], dashPhase: CGFloat(pulsePhase * 50))
            )
            .scaleEffect(1.0 + sin(pulsePhase * 4) * 0.08)
            .opacity(0.7 + sin(pulsePhase * 3) * 0.2)
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    pulsePhase = .pi * 2
                }
            }
    }
}

// MARK: - Center Waveform

struct CenterWaveform: View {
    let audioLevel: Float
    let isRecording: Bool
    let isProcessing: Bool
    @State private var symbolPhase: Double = 0
    
    var body: some View {
        ZStack {
            if isProcessing {
                // Spinning progress
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(
                            colors: [.teal, .blue, .purple, .pink, .teal],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(symbolPhase))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            symbolPhase = 360
                        }
                    }
                
                // Inner dot
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 8, height: 8)
            } else if isRecording {
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { index in
                        let phaseOffset = Double(index) * 0.7
                        let amplitude = max(0.22, CGFloat(audioLevel))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.9))
                            .frame(
                                width: 6,
                                height: 14 + amplitude * 34 * abs(sin(symbolPhase * 3 + phaseOffset))
                            )
                    }
                }
                .shadow(color: .teal.opacity(0.7), radius: 10)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        symbolPhase = 1
                    }
                }
            } else {
                AppLogoMarkView(size: 34)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Mini Waveform

struct MiniWaveformView: View {
    let levels: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            let barCount = min(levels.count, 40)
            let barWidth = geometry.size.width / CGFloat(barCount + barCount - 1)
            let maxHeight = geometry.size.height
            
            HStack(alignment: .bottom, spacing: barWidth) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = levels[i]
                    let height = max(maxHeight * CGFloat(level), 3)
                    
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1.0),
                                    Color(red: 0.6, green: 0.4, blue: 1.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: height)
                        .animation(.spring(response: 0.1, dampingFraction: 0.7), value: levels[i])
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
    }
}

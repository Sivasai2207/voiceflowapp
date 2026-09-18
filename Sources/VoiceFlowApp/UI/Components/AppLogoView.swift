import SwiftUI
import AppKit

/// Renders the official VoiceFlow app icon (squircle with gradient background and glow)
struct AppIconView: View {
    var size: CGFloat = 64
    var showShadow: Bool = true
    
    var body: some View {
        Group {
            if let image = loadAppIcon() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback squircle icon
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.2237)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.13, green: 0.16, blue: 0.20), Color(red: 0.06, green: 0.08, blue: 0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.2237)
                                .stroke(Color.white.opacity(0.16), lineWidth: max(1, size * 0.008))
                        )
                    
                    AppLogoMarkView(size: size * 0.65)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal, Color(red: 0.0, green: 0.8, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: showShadow ? Color.black.opacity(0.25) : .clear, radius: size * 0.08, x: 0, y: size * 0.04)
    }
    
    private func loadAppIcon() -> NSImage? {
        // Try Bundle.module asset catalog
        if let img = NSImage(named: "AppIcon256") {
            return img
        }
        // Try loading directly from resources directory
        if let resourceURL = Bundle.module.url(forResource: "AppIcon256", withExtension: "png"),
           let img = NSImage(contentsOf: resourceURL) {
            return img
        }
        // Try dist resources or project root
        let possiblePaths = [
            Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns",
            "/Users/sivasai/Projects/VoiceFlowApp/AppIcon.icns",
            "/Users/sivasai/Projects/VoiceFlowApp/Sources/VoiceFlowApp/Resources/AppIcon256.png"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }
}

/// Renders the official VoiceFlow logo mark (waveform bars + circle) as an adaptive template
struct AppLogoMarkView: View {
    var size: CGFloat = 28
    
    var body: some View {
        Group {
            if let image = loadLogoImage() {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Vector fallback if image not found
                VoiceFlowLogoShape()
                    .aspectRatio(918.0 / 812.0, contentMode: .fit)
            }
        }
        .frame(width: size, height: size * (812.0 / 918.0))
    }
    
    private func loadLogoImage() -> NSImage? {
        // Try loading from Assets or Resources
        if let img = NSImage(named: "AppLogo") {
            img.isTemplate = true
            return img
        }
        if let resourceURL = Bundle.module.url(forResource: "AppLogoMark", withExtension: "png"),
           let img = NSImage(contentsOf: resourceURL) {
            img.isTemplate = true
            return img
        }
        let possiblePaths = [
            "/Users/sivasai/Projects/VoiceFlowApp/Sources/VoiceFlowApp/Resources/AppLogoMark.png",
            "/Users/sivasai/Projects/VoiceFlowApp/Sources/VoiceFlowApp/Resources/Assets.xcassets/AppLogo.imageset/AppLogo.png"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }
}

/// Vector shape matching the exact VoiceFlow waveform and 'O' logo geometry
struct VoiceFlowLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Bars on left: 4 vertical rounded capsules with increasing heights
        let barWidth = w * 0.045
        let barSpacing = w * 0.065
        let barXStart = w * 0.23
        let heights: [CGFloat] = [0.18, 0.42, 0.65, 0.82]
        
        for (i, barHeightRatio) in heights.enumerated() {
            let barH = h * barHeightRatio
            let barX = barXStart + CGFloat(i) * barSpacing
            let barY = (h - barH) / 2
            let barRect = CGRect(x: barX, y: barY, width: barWidth, height: barH)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        
        // Circular 'O' on right with cutout
        let circleCenterX = w * 0.60
        let circleCenterY = h * 0.50
        let outerRadius = h * 0.41
        let innerRadius = h * 0.23
        
        // Outer arc/circle
        path.addEllipse(in: CGRect(
            x: circleCenterX - outerRadius,
            y: circleCenterY - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        
        // Inner cutout
        path.addEllipse(in: CGRect(
            x: circleCenterX - innerRadius,
            y: circleCenterY - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
        
        return path
    }
}

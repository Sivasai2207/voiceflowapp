import Foundation
import AVFoundation

@MainActor
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()
    
    private init() {}
    
    var availableInputs: [AudioDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices.map { AudioDevice(device: $0) }
    }
    
    var currentInput: AudioDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices.first.map { AudioDevice(device: $0) }
    }
    
    func setPreferredInput(_ device: AudioDevice?) {
        // On macOS, we can't programmatically set the default input device
        // This would require user action in System Settings
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    
    init(device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.isBuiltIn = device.deviceType == .microphone
    }
}

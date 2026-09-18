import Foundation
import OSLog
import FluidAudio

actor ModelStore {
    static let shared = ModelStore()
    
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "ModelStore")
    private let fileManager = FileManager.default
    
    private var modelsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceFlowApp/Models", isDirectory: true)
    }
    
    func parakeetModelURL() -> URL {
        modelsDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
    }
    
    func isParakeetModelInstalled() -> Bool {
        AsrModels.modelsExist(at: parakeetModelURL(), version: .v3)
    }
    
    func getModelSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
    
    func removeParakeetModel() async throws {
        let modelDir = parakeetModelURL()
        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
            logger.info("Parakeet model removed")
        }
    }
    
    func ensureModelsDirectory() throws {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
}

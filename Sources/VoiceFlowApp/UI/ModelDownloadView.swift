import SwiftUI
import FluidAudio

@available(macOS 14.0, *)
struct ModelDownloadView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var downloadProgress: Double = 0
    @State private var downloadState: DownloadState = .idle
    @State private var errorMessage: String?
    
    enum DownloadState {
        case idle
        case downloading
        case completed
        case failed(String)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.teal)
            
            VStack(spacing: 8) {
                Text("Download Parakeet Model")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Parakeet TDT 0.6B v3 — 25 languages, ~480 MB installed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            switch downloadState {
            case .idle:
                Button("Start Download") {
                    startDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .downloading:
                VStack(spacing: 12) {
                    ProgressView(value: downloadProgress, total: 1.0)
                        .frame(width: 300)
                    
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.teal)
                    
                    Text("Downloading model files...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    
                    Text("Model Ready!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    
                    Text("Download Failed")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(40)
        .frame(width: 440, height: 380, alignment: .center)
        .background(.regularMaterial)
    }
    
    private func startDownload() {
        downloadState = .downloading
        downloadProgress = 0
        errorMessage = nil
        
        Task {
            do {
                try await ModelStore.shared.ensureModelsDirectory()
                let modelURL = await ModelStore.shared.parakeetModelURL()
                
                _ = try await AsrModels.downloadAndLoad(
                    to: modelURL,
                    version: .v3,
                    progressHandler: { progress in
                        Task { @MainActor in
                            downloadProgress = progress.fractionCompleted
                        }
                    }
                )
                
                await MainActor.run {
                    downloadProgress = 1.0
                    downloadState = .completed
                }
            } catch {
                await MainActor.run {
                    downloadState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

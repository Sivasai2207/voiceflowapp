import Foundation
import AVFoundation
import Accelerate
import OSLog

actor AudioPipeline {
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "AudioPipeline")
    private var appleConverter: AVAudioConverter?
    private var retainedAudioBuffer: [Float] = []
    private let maxRetainedSamples = 16000 * 120
    private var sourceFormat: AVAudioFormat?
    private var targetAppleFormat: AVAudioFormat?
    
    func prepare(forAppleFormat appleFormat: AVAudioFormat, sourceFormat: AVAudioFormat) {
        self.sourceFormat = sourceFormat
        self.targetAppleFormat = appleFormat
        
        if appleFormat != sourceFormat {
            appleConverter = AVAudioConverter(from: sourceFormat, to: appleFormat)
        }
    }
    
    func processForAppleSamples(_ samples: [Float], format: AVAudioFormat) -> [Float]? {
        guard let converter = appleConverter,
              let targetFormat = targetAppleFormat else {
            // If no converter needed, just resample if needed
            var result = samples
            if format.sampleRate != targetAppleFormat?.sampleRate, let tf = targetAppleFormat {
                result = resample(result, from: format.sampleRate, to: tf.sampleRate)
            }
            if format.channelCount > 1 {
                result = downmixToMono(result, channels: Int(format.channelCount))
            }
            return result
        }
        
        // Convert using AVAudioConverter
        let ratio = targetFormat.sampleRate / format.sampleRate
        let outputFrames = AVAudioFrameCount(Double(samples.count) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            var result = samples
            if format.sampleRate != targetFormat.sampleRate {
                result = resample(result, from: format.sampleRate, to: targetFormat.sampleRate)
            }
            if format.channelCount > 1 {
                result = downmixToMono(result, channels: Int(format.channelCount))
            }
            return result
        }
        
        // Create input buffer from samples
        let inputFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount)!
        let inputFrameCount = AVAudioFrameCount(samples.count / Int(format.channelCount))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            var result = samples
            if format.sampleRate != targetFormat.sampleRate {
                result = resample(result, from: format.sampleRate, to: targetFormat.sampleRate)
            }
            if format.channelCount > 1 {
                result = downmixToMono(result, channels: Int(format.channelCount))
            }
            return result
        }
        
        inputBuffer.frameLength = inputFrameCount
        if format.channelCount == 1 {
            if let channelData = inputBuffer.floatChannelData?[0] {
                channelData.initialize(from: samples, count: samples.count)
            }
        } else {
            // Interleave for multi-channel
            for i in 0..<Int(inputFrameCount) {
                for c in 0..<Int(format.channelCount) {
                    if let channelData = inputBuffer.floatChannelData?[c] {
                        channelData[i] = samples[i * Int(format.channelCount) + c]
                    }
                }
            }
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            // Create input buffer inside the closure to avoid Sendable capture
            let localInputFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount)!
            let localInputFrameCount = AVAudioFrameCount(samples.count / Int(format.channelCount))
            guard let localInputBuffer = AVAudioPCMBuffer(pcmFormat: localInputFormat, frameCapacity: localInputFrameCount) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            localInputBuffer.frameLength = localInputFrameCount
            if format.channelCount == 1 {
                if let channelData = localInputBuffer.floatChannelData?[0] {
                    channelData.initialize(from: samples, count: samples.count)
                }
            } else {
                for i in 0..<Int(localInputFrameCount) {
                    for c in 0..<Int(format.channelCount) {
                        if let channelData = localInputBuffer.floatChannelData?[c] {
                            channelData[i] = samples[i * Int(format.channelCount) + c]
                        }
                    }
                }
            }
            return localInputBuffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            logger.error("Apple conversion error: \(error)")
            var result = samples
            if format.sampleRate != targetFormat.sampleRate {
                result = resample(result, from: format.sampleRate, to: targetFormat.sampleRate)
            }
            if format.channelCount > 1 {
                result = downmixToMono(result, channels: Int(format.channelCount))
            }
            return result
        }
        
        return extractFloatSamples(from: outputBuffer)
    }
    
    func processForParakeetSamples(_ samples: [Float], format: AVAudioFormat) -> [Float] {
        var result = samples
        
        if format.sampleRate != 16000 {
            result = resample(result, from: format.sampleRate, to: 16000)
        }
        
        if format.channelCount > 1 {
            result = downmixToMono(result, channels: Int(format.channelCount))
        }
        
        retainAudio(result)
        
        return result
    }
    
    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
    
    private func retainAudio(_ samples: [Float]) {
        retainedAudioBuffer.append(contentsOf: samples)
        
        if retainedAudioBuffer.count > maxRetainedSamples {
            let excess = retainedAudioBuffer.count - maxRetainedSamples
            retainedAudioBuffer.removeFirst(excess)
        }
    }
    
    func getRetainedAudio() -> [Float] {
        retainedAudioBuffer
    }
    
    func clearRetainedAudio() {
        retainedAudioBuffer.removeAll(keepingCapacity: true)
    }
    
    private func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        let ratio = targetRate / sourceRate
        let outputCount = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputCount)
        
        var inputIndex: Double = 0
        let inputCount = samples.count
        for i in 0..<outputCount {
            let exactIndex = inputIndex
            let index = Int(exactIndex)
            let frac = Float(exactIndex - Double(index))
            
            if index + 1 < inputCount {
                output[i] = samples[index] + frac * (samples[index + 1] - samples[index])
            } else if index < inputCount {
                output[i] = samples[index]
            } else {
                output[i] = 0
            }
            
            inputIndex += 1.0 / ratio
        }
        
        return output
    }
    
    private func downmixToMono(_ samples: [Float], channels: Int) -> [Float] {
        let frameCount = samples.count / channels
        var mono = [Float](repeating: 0, count: frameCount)
        
        for i in 0..<frameCount {
            var sum: Float = 0
            for c in 0..<channels {
                sum += samples[i * channels + c]
            }
            mono[i] = sum / Float(channels)
        }
        
        return mono
    }
}
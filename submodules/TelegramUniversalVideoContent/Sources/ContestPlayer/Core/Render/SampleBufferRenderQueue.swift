import Foundation
import AVFoundation

final class SampleBufferRenderQueue {
    enum Result {
        case finished
        case waiting
        case skip
        case frame(CMSampleBuffer)
    }
    
    private let mediaType: AVMediaType
    
    private var samplesQueue: [CMSampleBuffer] = []
    private var prebufferedDuration: CMTime = .zero
    
    private var queue = [SampleBufferProducer]()
    private var pointer: Int = 0
    
    private var lastProducerOffset: CMTime
    private var lastFramePts = CMTime.zero
    
    private var isCompleted = false
    
    private let bufferSyncQueue = DispatchQueue(label: "TGPlayer.BufferSyncQueue")
    
    init(mediaType: AVMediaType, startTime: CMTime) {
        self.mediaType = mediaType
        self.lastProducerOffset = startTime
    }
    
    func dequeue(targetTime: CMTime) -> Result {
        bufferSyncQueue.sync {
            if pointer >= queue.count {
                if samplesQueue.isEmpty {
                    return isCompleted ? .finished : .waiting
                }
                
                let sample = samplesQueue.removeFirst()
                prebufferedDuration = CMTimeSubtract(prebufferedDuration, CMSampleBufferGetDuration(sample))
                return .frame(sample)
            }
            
            let current = queue[pointer]
            
            guard !current.isFinished else {
                pointer += 1
                lastProducerOffset = lastFramePts
                lastFramePts = CMTime.zero
                return .skip
            }
            
            guard let sampleBuffer = current.produce() else {
                return .skip
            }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if !pts.isValid {
                return .skip
            }
            
            let lastProducerOffsetConverted = CMTimeConvertScale(lastProducerOffset, timescale: pts.timescale, method: .default)
            let newPts = CMTime(value: lastProducerOffsetConverted.value + pts.value, timescale: pts.timescale)
            
            CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: newPts)
            
            lastFramePts = CMTimeMaximum(lastFramePts, newPts)
            samplesQueue.append(sampleBuffer)
            prebufferedDuration = CMTimeAdd(prebufferedDuration, CMSampleBufferGetDuration(sampleBuffer))
            
            if samplesQueue.isEmpty {
                return .waiting
            }
            
            let sample = samplesQueue.removeFirst()
            prebufferedDuration = CMTimeSubtract(prebufferedDuration, CMSampleBufferGetDuration(sample))
            
            return .frame(sample)
        }
    }
    
    func enqueue(asset: AVAsset, timeOffset: CMTime) {
        guard let producer = makeProducer(for: asset, timeOffset: timeOffset) else {
            return
        }
        
        bufferSyncQueue.async { [self] in
            self.queue.append(producer)
        }
    }
    
    func complete() {
        isCompleted = true
    }

    private func makeProducer(for asset: AVAsset, timeOffset: CMTime) -> SampleBufferProducer? {
        SampleBufferProducer(asset: asset, mediaType: mediaType, timeOffset: timeOffset)
    }
}

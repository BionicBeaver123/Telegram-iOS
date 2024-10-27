import Foundation
import AVFoundation

final class RenderTarget<Target: AVQueuedSampleBufferRendering> {
    enum Status: Equatable {
        case playing
        case finished
        case waiting
    }
    
    private weak var target: Target?
    
    private var renderBuffer: SampleBufferRenderQueue
    private let renderQueue: DispatchQueue
    private let mediaType: AVMediaType
    
    private var status: Status = .finished {
        didSet {
            if oldValue != status {
                onStatusChange?(status)
            }
        }
    }
    
    private let onStatusChange: ((Status) -> Void)?
    private let onWaitingIntervalEnd: ((TimeInterval) -> Void)?
    
    private var waitingIntervalStarted: TimeInterval? = CACurrentMediaTime()
    private let startTime: CMTime
    
    init(
        target: Target, 
        mediaType: AVMediaType,
        startTime: CMTime,
        renderQueue: DispatchQueue = DispatchQueue(label: "TGPlayer.RenderLoop", qos: .userInitiated),
        onStatusChange: ((Status) -> Void)?,
        onWaitingIntervalEnd: ((TimeInterval) -> Void)?
    ) {
        self.startTime = startTime
        self.target = target
        self.renderQueue = renderQueue
        self.renderBuffer = SampleBufferRenderQueue(mediaType: mediaType, startTime: startTime)
        self.mediaType = mediaType
        self.onStatusChange = onStatusChange
        self.onWaitingIntervalEnd = onWaitingIntervalEnd
    }
    
    func waitForEnqueue() {
        guard let target else {
            return
        }

        target.requestMediaDataWhenReady(on: renderQueue) { [self] in
            while target.isReadyForMoreMediaData {
                let targetTime = CMTimebaseGetTime(target.timebase)
                
                switch renderBuffer.dequeue(targetTime: targetTime) {
                case .finished:
                    status = .finished
                    stop()
                    return
                    
                case let .frame(buffer):
                    status = .playing
                    
                    if let waitingIntervalStarted {
                        self.onWaitingIntervalEnd?(CACurrentMediaTime() - waitingIntervalStarted)
                        self.waitingIntervalStarted = nil
                    }
                    
                    target.enqueue(buffer)
                    
                case .skip:
                    continue
                    
                case .waiting:
                    status = .waiting
                    
                    if waitingIntervalStarted == nil {
                        waitingIntervalStarted = CACurrentMediaTime()
                    }
                    
                    usleep(10000)
                }
            }
        }
    }
    
    func enqueue(asset: AVAsset, timeOffset: CMTime) {
        renderBuffer.enqueue(asset: asset, timeOffset: timeOffset)
    }
    
    func complete() {
        renderBuffer.complete()
    }
    
    func stop() {
        renderBuffer.complete()
        target?.flush()
        target?.stopRequestingMediaData()
    }
}

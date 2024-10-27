import Foundation
import AVFoundation

protocol TGTargetRendering: AnyObject {
    func prepare(startTimeOffset: CMTime)
    func enqueueFile(withURL url: URL, timeOffset: CMTime)
    func cancel()
    func complete()
}

enum PlaybackStatus {
    case playing
    case finished
    case buffering
}

typealias PlaybackStatusChangeCallback = (PlaybackStatus) -> Void

protocol TGVideoRendering: TGTargetRendering, AVQueuedSampleBufferRendering {
    func attach(player: TGPlayer)
    func observeStatus(_ onStatusChange: @escaping PlaybackStatusChangeCallback)
    func observeQualityDownchangeRequest(_ onQualityChangeRequest: @escaping () -> Void)
}

class TGPlayerLayer: AVSampleBufferDisplayLayer, TGVideoRendering {
    private var renderLoop: RenderTarget<AVSampleBufferDisplayLayer>?
    private var onStatusChange: PlaybackStatusChangeCallback?
    private var onQualityChangeRequest: (() -> Void)?
    
    func prepare(startTimeOffset: CMTime) {
        renderLoop = RenderTarget(
            target: self,
            mediaType: .video,
            startTime: startTimeOffset,
            onStatusChange: { [weak self] newStatus in
                switch newStatus {
                case .playing:
                    self?.onStatusChange?(.playing)
                case .finished:
                    self?.onStatusChange?(.finished)
                case .waiting:
                    self?.onStatusChange?(.buffering)
                }
            },
            onWaitingIntervalEnd: { [weak self] duration in
                if duration >= 4.0 {
                    self?.onQualityChangeRequest?()
                }
            }
        )
        renderLoop?.waitForEnqueue()
    }
    
    func enqueueFile(withURL url: URL, timeOffset: CMTime) {
        guard let renderLoop = self.renderLoop else {
            assertionFailure("Call prepare() before enqueue assets")
            return
        }
        
        let asset = AVAsset(url: url)
        renderLoop.enqueue(asset: asset, timeOffset: timeOffset)
    }
    
    func attach(player: TGPlayer) {
        player.attach(layer: self)
    }
    
    func observeStatus(_ onStatusChange: @escaping PlaybackStatusChangeCallback) {
        self.onStatusChange = onStatusChange
    }
    
    func observeQualityDownchangeRequest(_ onQualityChangeRequest: @escaping () -> Void) {
        self.onQualityChangeRequest = onQualityChangeRequest
    }
    
    func complete() {
        renderLoop?.complete()
    }
    
    func cancel() {
        renderLoop?.stop()
        renderLoop = nil
    }
}

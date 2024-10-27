import Foundation
import AVFoundation

protocol TGAudioRendering: TGTargetRendering, AVQueuedSampleBufferRendering {
    var volume: Float { get set }
}

class TGAudioRenderer: AVSampleBufferAudioRenderer, TGAudioRendering {
    private var renderLoop: RenderTarget<AVSampleBufferAudioRenderer>?
    private var onStatusChange: PlaybackStatusChangeCallback?
    
    func prepare(startTimeOffset: CMTime) {
        renderLoop = RenderTarget(
            target: self,
            mediaType: .audio,
            startTime: startTimeOffset,
            onStatusChange: nil,
            onWaitingIntervalEnd: nil
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
    
    func cancel() {
        renderLoop?.stop()
        renderLoop = nil
    }
    
    func complete() {
        renderLoop?.complete()
    }
}

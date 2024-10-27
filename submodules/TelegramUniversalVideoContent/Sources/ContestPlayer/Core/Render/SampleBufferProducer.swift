import Foundation
import AVFoundation

final class SampleBufferProducer {
    let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    
    private var isReadingStarted = false
    private(set) var isFinished = false
    
    init?(asset: AVAsset, mediaType: AVMediaType, timeOffset: CMTime) {
        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        
        reader.timeRange = CMTimeRange(start: timeOffset, end: CMTime.positiveInfinity)
        
        self.reader = reader
        
        guard let track = asset.tracks(withMediaType: mediaType).first else {
            return nil
        }
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        
        self.output = output
    }
    
    func produce() -> CMSampleBuffer? {
        if !isReadingStarted {
            if reader.startReading() {
                isReadingStarted = true
            } else {
                return nil
            }
        }
        
        let buffer = output.copyNextSampleBuffer()
        
        isFinished = reader.status != .unknown && buffer == nil
        
        if isFinished {
            reader.cancelReading()
        }
        
        return buffer
    }
}

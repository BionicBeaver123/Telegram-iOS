import CoreMedia

extension M3U8.MediaPlaylist {
    func getSegmentsToSkipCount(startingFrom time: TimeInterval) -> Int {
        var totalDuration: TimeInterval = 0
        var countToDrop = 0
        for segment in self.segments {
            if time >= totalDuration && time < totalDuration + (segment.duration ?? 0) {
                break
            }
            totalDuration += segment.duration ?? 0
            countToDrop += 1
        }
        
        return countToDrop
    }
    
    func getSegmentOffset(containing time: CMTime) -> CMTime {
        var currentTime: CMTime = .zero
        
        for segment in segments {
            if currentTime <= time && time < CMTimeAdd(currentTime, CMTime(seconds: segment.duration ?? 0)) {
                break
            }
            currentTime = CMTimeAdd(currentTime, CMTime(seconds: segment.duration ?? 0))
        }
        return currentTime
    }
}

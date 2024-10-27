import Foundation

final class BandwidthCalculator {
    static let shared = BandwidthCalculator()
    
    var bandwidth: Int? {
        // ignore calculations if less than 4 records
        return buffer.count < 4 ? nil : _bandwidth
    }
    
    private var _bandwidth: Int {
        if buffer.isEmpty { return 0 }
        return buffer.reduce(0, +) / buffer.count
    }
    
    @ThreadSafe
    private var buffer: [Int] = []
    
    init() { }
    
    func add(time: TimeInterval, bytes: Int) {
        guard !time.isZero, bytes > 0 else {
            return
        }
        
        let shrinkThreshold = 20
        if buffer.count == shrinkThreshold {
            buffer = [_bandwidth]
        }
        
        buffer.append(Int(Double(bytes) * 8.0 / time))
    }
}

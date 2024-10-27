import Foundation
import QuartzCore

final class StreamDataProvider: NSObject, ContentDataProvider {
    private var offset = 0
    private var buffer = Data()
    private var mutex = pthread_mutex_t()
    private var onDataReceive: [DataReceiveCallback] = []
    private let onError: (Error) -> Void
    
    private(set) var isFinished = false
    
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private let url: URL
    private let rangeOffset: Int?
    private var startLoadTime = CACurrentMediaTime()
    
    init(
        url: URL,
        rangeOffset: Int? = nil,
        onError: @escaping (Error) -> Void
    ) {
        self.onError = onError
        self.url = url
        self.rangeOffset = rangeOffset
        
        pthread_mutex_init(&mutex, nil)
    }
    
    func receive(_ callback: @escaping DataReceiveCallback) {
        onDataReceive.append(callback)
    }
    
    func resumeIfNeeded() {
        if dataTask != nil {
            return
        }
        
        startLoadTime = CACurrentMediaTime()
        
        let session = self.session ?? URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        if self.session == nil {
            self.session = session
        }
        
        var request = URLRequest(url: url, timeoutInterval: TimeInterval.infinity)
        
        if let rangeOffset, rangeOffset > 0 {
            request.addValue("bytes=\(rangeOffset)-", forHTTPHeaderField: "Range")
        }
        
        let task = session.dataTask(with: request)
        task.resume()
        
        offset = rangeOffset ?? 0
        dataTask = task
    }
    
    func stopIfNeeded() {
        dataTask?.cancel()
        dataTask = nil
    }
    
    private func makeConsumer() -> (Int) -> Data? {
        let consumingCallback: (Int) -> Data? = { [self] requestedBytesCount in
            defer {
                pthread_mutex_unlock(&self.mutex)
            }
            
            if requestedBytesCount == 0 {
                return nil
            }
            
            if self.buffer.count < requestedBytesCount {
                return nil
            }
            
            let prefix = self.buffer.prefix(requestedBytesCount)
            self.buffer.removeFirst(requestedBytesCount)
            return prefix
        }
        return consumingCallback
    }
}

extension StreamDataProvider: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        pthread_mutex_lock(&mutex)
        
        BandwidthCalculator.shared.add(time: CACurrentMediaTime() - startLoadTime, bytes: data.count)
        startLoadTime = CACurrentMediaTime()
        
        buffer.append(data)
        
        onDataReceive.forEach {
            do {
                try $0(makeConsumer(), offset)
            } catch {
                onError(error)
            }
        }
        
        offset += data.count
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            onError(error)
        } else {
            isFinished = true
            
            while !buffer.isEmpty {
                pthread_mutex_lock(&mutex)
                
                onDataReceive.forEach {
                    do {
                        try $0(makeConsumer(), offset)
                    } catch {
                        onError(error)
                    }
                }
                
                // sleep to prevent frequent small chunks reading
                usleep(10000)
            }
        }
    }
}

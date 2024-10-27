import Foundation
import QuartzCore

typealias DataReceiveCallback = (_ consumer: @escaping (Int) -> Data?, _ offset: Int) throws -> Void

protocol ContentDataProvider {
    func resumeIfNeeded()
    func stopIfNeeded()
    func receive(_ callback: @escaping DataReceiveCallback)
}

final class FileDataProvider: NSObject, ContentDataProvider {
    struct Error: Swift.Error { }
    
    private static let urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    
    private var onDataReceive: DataReceiveCallback?
    private let onError: (Swift.Error) -> Void
    private let byteRange: (length: Int, offset: Int)?
    
    private(set) var isFinished = false
    private var task: URLSessionTask?
    
    private let url: URL
    private let serialExecutionSemaphore: DispatchSemaphore
    
    init(
        url: URL,
        byteRange: (length: Int, offset: Int)?,
        serialExecutionSemaphore: DispatchSemaphore,
        onError: @escaping (Swift.Error) -> Void
    ) {
        self.onError = onError
        self.serialExecutionSemaphore = serialExecutionSemaphore
        self.byteRange = byteRange
        self.url = url
    }
    
    func receive(_ callback: @escaping DataReceiveCallback) {
        onDataReceive = callback
    }
    
    func resumeIfNeeded() {
        serialExecutionSemaphore.wait()
        
        var request = URLRequest(url: url, timeoutInterval: TimeInterval.infinity)
        
        if let byteRange {
            request.addValue("bytes=\(byteRange.offset)-\(byteRange.offset + byteRange.length - 1)", forHTTPHeaderField: "Range")
        }
        
        let startLoadTime = CACurrentMediaTime()
        
        let task = Self.urlSession.downloadTask(with: request) { [weak self, serialExecutionSemaphore] url, _, error in
            defer {
                serialExecutionSemaphore.signal()
            }
            
            guard let self else {
                return
            }
            
            if let error {
                self.onError(error)
            } else if let url {
                do {
                    let data = try? Data(contentsOf: url)
                    
                    BandwidthCalculator.shared.add(time: CACurrentMediaTime() - startLoadTime, bytes: data?.count ?? 0)
                    
                    try self.onDataReceive?({ _ in data }, byteRange?.offset ?? 0)
                } catch {
                    self.onError(error)
                }
            } else {
                self.onError(Error())
            }
        }
        
        task.resume()
        
        self.task = task
    }
    
    func stopIfNeeded() {
        task?.cancel()
    }
}

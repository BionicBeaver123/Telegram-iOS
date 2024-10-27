import Foundation

final class ContentDataProviderCache {
    static let shared = ContentDataProviderCache()
    
    @ThreadSafe
    var files: [DownloadSession.BytesHashKey: URL] = [:]
    
    func removeAll() {
        let files = files
        self.files.removeAll()
        
        files.values.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
    }
}

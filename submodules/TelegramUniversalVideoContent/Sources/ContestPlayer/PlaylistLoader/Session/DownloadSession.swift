import Foundation
import AVFoundation

final class DownloadSession {
    struct BytesHashKey: Hashable {
        let offset: Int
        let length: Int
        let uri: String
    }
    
    struct SessionHashKey: Hashable {
        let url: URL
        let offset: Int?
    }
    
    enum Mode {
        case stream(readOffsetInBytes: Int, byteRange: M3U8.ByteRange)
        case file(byteRange: M3U8.ByteRange?)
    }

    @ThreadSafe
    private var providers: [SessionHashKey: Int] = [:]
    
    @ThreadSafe
    private var providersStorage: [ContentDataProvider] = []
    
    @ThreadSafe
    private var initializationSections: [BytesHashKey: Data] = [:]
    
    @ThreadSafe
    private var loadedChunks = Set<BytesHashKey>()
    
    private let loadSerialSemaphore = DispatchSemaphore(value: 1)
    
    private let id: String
    private let resultQueue: DispatchQueue
    private let resumeSerialQueue = DispatchQueue(label: "TGPlayer.FileSessionLoading", qos: .default)
    
    private let completion: (Int, URL) -> Void
    
    init(id: String, resultQueue: DispatchQueue, completion: @escaping (Int, URL) -> Void) {
        self.id = id
        self.completion = completion
        self.resultQueue = resultQueue
        
        print("Init download session, id=\(id)")
    }
    
    deinit {
        stop()
        print("Deinit download session, id=\(id)")
    }
    
    func addInitializationSection(index: Int, url: URL, mode: Mode) {
        switch mode {
        case let .stream(_, byteRange):
            loadInitializationSectionWithStream(url: url, byteRange: byteRange)
        case let .file(byteRange):
            loadInitializationSectionWithFile(url: url, byteRange: byteRange)
        }
    }
    
    func addSegment(
        index: Int, 
        url: URL,
        mode: Mode,
        initializationSection: M3U8.MediaPlaylist.Segment.InitializationSection?
    ) {
        switch mode {
        case let .stream(offset, byteRange):
            loadSegmentWithStream(
                index: index,
                url: url,
                readFromOffset: offset,
                byteRange: byteRange,
                initializationSection: initializationSection
            )
        case let .file(byteRange):
            loadSegmentWithFile(
                index: index,
                url: url,
                byteRange: byteRange,
                initializationSection: initializationSection
            )
        }
    }
    
    func start() {
        for provider in providersStorage {
            resumeSerialQueue.async {
                provider.resumeIfNeeded()
            }
        }
    }
    
    func stop() {
        providersStorage.forEach { $0.stopIfNeeded() }
    }
    
    private func loadInitializationSectionWithStream(url: URL, byteRange: M3U8.ByteRange) {
        let sectionKey = BytesHashKey(offset: byteRange.offset, length: byteRange.length, uri: url.lastPathComponent)
        
        if let cachedFileURL = ContentDataProviderCache.shared.files[sectionKey],
           let cachedData = try? Data(contentsOf: cachedFileURL) {
            self.initializationSections[sectionKey] = cachedData
            self.loadedChunks.insert(sectionKey)
            return
        }
        
        if initializationSections[sectionKey] == nil {
            initializationSections[sectionKey] = .init()
            
            let session = getOrCreateStreamDataProvider(for: url, offset: byteRange.offset)
            session.receive { [weak self] consumer, offset in
                guard let self else {
                    return
                }
                
                if offset < byteRange.offset || loadedChunks.contains(sectionKey) {
                    _ = consumer(0)
                } else if let data = consumer(byteRange.length) {
                    initializationSections[sectionKey] = data
                    loadedChunks.insert(sectionKey)
                }
            }
        }
    }
    
    private func loadInitializationSectionWithFile(url: URL, byteRange: M3U8.ByteRange?) {
        let sectionKey = BytesHashKey(
            offset: byteRange?.offset ?? 0,
            length: byteRange?.length ?? -1,
            uri: url.lastPathComponent
        )
        
        if let cachedFileURL = ContentDataProviderCache.shared.files[sectionKey],
           let cachedData = try? Data(contentsOf: cachedFileURL) {
            self.initializationSections[sectionKey] = cachedData
            self.loadedChunks.insert(sectionKey)
            return
        }
        
        if initializationSections[sectionKey] == nil {
            initializationSections[sectionKey] = .init()
            
            let session = getOrCreateFileDataProvider(for: url, byteRange: byteRange)
            session.receive { [weak self] consumer, offset in
                guard let self else {
                    return
                }
                
                if self.loadedChunks.contains(sectionKey) {
                    return
                }
                
                self.initializationSections[sectionKey] = consumer(-1)
                self.loadedChunks.insert(sectionKey)
            }
        }
    }
    
    private func loadSegmentWithStream(
        index: Int,
        url: URL,
        readFromOffset offset: Int = 0,
        byteRange: M3U8.ByteRange,
        initializationSection: M3U8.MediaPlaylist.Segment.InitializationSection?
    ) {
        let segmentKey = BytesHashKey(offset: byteRange.offset, length: byteRange.length, uri: url.lastPathComponent)
        
        if let cachedFileURL = ContentDataProviderCache.shared.files[segmentKey] {
            resultQueue.async { [completion] in
                completion(index, cachedFileURL)
            }
            return
        }
        
        let session = getOrCreateStreamDataProvider(for: url, offset: offset)
        
        session.receive { [weak self] consumer, offset in
            guard let self else {
                return
            }
            
            if offset < byteRange.offset || loadedChunks.contains(segmentKey) {
                _ = consumer(0)
            } else if let data = consumer(byteRange.length) {
                loadedChunks.insert(segmentKey)
                
                let initializationSectionData = initializationSection.flatMap {
                    self.getLoadedInitializationSection($0)
                } ?? .init()
                
                let fullSegmentData = initializationSectionData + data
                
                let url = try writeDataToTemporaryFile(
                    fullSegmentData,
                    filename: [
                        id,
                        "\(url.absoluteString.hashValue)",
                        "\(index)",
                        "\(segmentKey.offset)",
                        "\(segmentKey.length)"
                    ].joined(separator: "_") + ".mp4"
                )
                
                ContentDataProviderCache.shared.files[segmentKey] = url
                
                resultQueue.async { [completion] in
                    completion(index, url)
                }
            }
        }
    }
    
    private func loadSegmentWithFile(
        index: Int,
        url: URL,
        byteRange: M3U8.ByteRange?,
        initializationSection: M3U8.MediaPlaylist.Segment.InitializationSection?
    ) {
        let segmentKey = BytesHashKey(
            offset: byteRange?.offset ?? 0,
            length: byteRange?.length ?? 1,
            uri: url.lastPathComponent
        )
        
        if let cachedFileURL = ContentDataProviderCache.shared.files[segmentKey] {
            resultQueue.async { [completion] in
                completion(index, cachedFileURL)
            }
            return
        }
        
        let session = getOrCreateFileDataProvider(for: url, byteRange: byteRange)
        
        session.receive { [weak self] consumer, offset in
            guard let self else {
                return
            }
            
            if let data = consumer(-1), !self.loadedChunks.contains(segmentKey) {
                self.loadedChunks.insert(segmentKey)
                
                let initializationSectionData = initializationSection.flatMap {
                    self.getLoadedInitializationSection($0)
                } ?? .init()
                
                let fullSegmentData = initializationSectionData + data
                
                let url = try self.writeDataToTemporaryFile(
                    fullSegmentData,
                    filename: [
                        id,
                        "\(url.absoluteString.hashValue)",
                        "\(index)",
                        "\(segmentKey.offset)",
                        "\(segmentKey.length)"
                    ].joined(separator: "_") + ".mp4"
                )
                
                ContentDataProviderCache.shared.files[segmentKey] = url
                
                resultQueue.async { [completion] in
                    completion(index, url)
                }
            }
        }
    }
    
    private func writeDataToTemporaryFile(_ data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.absoluteString, contents: .init())
        try data.write(to: url)
        
        return url
    }
    
    private func getLoadedInitializationSection(_ section: M3U8.MediaPlaylist.Segment.InitializationSection) -> Data {
        if let byteRange = section.byteRange {
            let sectionKey = BytesHashKey(offset: byteRange.offset, length: byteRange.length, uri: section.uri)
            return initializationSections[sectionKey] ?? .init()
        } else {
            let sectionKey = BytesHashKey(offset: 0, length: -1, uri: section.uri)
            return initializationSections[sectionKey] ?? .init()
        }
    }
    
    private func getOrCreateStreamDataProvider(for url: URL, offset: Int) -> any ContentDataProvider {
        if let sessionIndex = providers[.init(url: url, offset: offset)] {
            return providersStorage[sessionIndex]
        } else {
            let session = StreamDataProvider(url: url, rangeOffset: offset) { error in
                print("Segment streaming error: \(error.localizedDescription)")
            }
            
            providers[.init(url: url, offset: offset)] = providersStorage.count
            providersStorage.append(session)
            return session
        }
    }
    
    private func getOrCreateFileDataProvider(for url: URL, byteRange: M3U8.ByteRange?) -> any ContentDataProvider {
        if let sessionIndex = providers[.init(url: url, offset: byteRange?.offset)] {
            return providersStorage[sessionIndex]
        } else {
            let session = FileDataProvider(
                url: url, 
                byteRange: byteRange.flatMap { (length: $0.length, offset: $0.offset) },
                serialExecutionSemaphore: loadSerialSemaphore
            ) { error in
                print("Segment loading error: \(error.localizedDescription)")
            }
            
            providers[.init(url: url, offset: byteRange?.offset)] = providersStorage.count
            providersStorage.append(session)
            return session
        }
    }
}

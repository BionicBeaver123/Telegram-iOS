import Foundation
import CoreMedia

final class PlaylistLoader {
    private let url: URL
    private let urlSession: URLSession
    
    private let baseURL: URL
    private(set) var supportsRanges = false
    
    init(
        url: URL, 
        urlSession: URLSession = URLSession.shared
    ) {
        self.url = url
        self.urlSession = urlSession
        
        baseURL = url.deletingLastPathComponent()
    }
    
    func load(time: CMTime = .zero, completion: @escaping (Result<M3U8.Playlist, Error>) -> Void) {
        let task = urlSession.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            guard let self else {
                completion(.failure(M3U8PlaylistLoaderError(message: "Unable to load playlist")))
                return
            }
            
            if let error {
                completion(.failure(M3U8PlaylistLoaderError(message: "Unable to load playlist: \(error)")))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                supportsRanges = (
                    (httpResponse.allHeaderFields["Accept-Ranges"] as? String) ??
                    (httpResponse.allHeaderFields["accept-ranges"] as? String) ??
                    (httpResponse.allHeaderFields["ACCEPT-RANGES"] as? String)
                ) == "bytes"
            }
            
            if let data {
                let parser = M3U8Parser(data: data)
                
                do {
                    let playlist = try parser.parseAsMaster()
                    completion(.success(.master(playlist)))
                } catch {
                    if let error = error as? M3U8ParserError, error == .mediaInsteadOfMaster {
                        self.loadMedia(playlistURL: url) {
                            switch $0 {
                            case let .success(playlist):
                                completion(.success(.media(playlist)))
                            case let .failure(error):
                                completion(.failure(error))
                            }
                        }
                    } else {
                        completion(.failure(error))
                    }
                }
            } else {
                completion(.failure(M3U8PlaylistLoaderError(message: "Unable to load playlist")))
            }
        }
        task.resume()
    }
    
    func loadMedia(uri: String, completion: @escaping (Result<M3U8.MediaPlaylist, Error>) -> Void) {
        guard let playlistURL = try? buildURL(for: uri) else {
            completion(.failure(M3U8PlaylistLoaderError(message: "Invalid media playlist url")))
            return
        }

        loadMedia(playlistURL: playlistURL, completion: completion)
    }
    
    func loadSegments(
        sessionID: String,
        streamURI: String,
        playlist: M3U8.MediaPlaylist,
        startTime: CMTime,
        resultQueue: DispatchQueue,
        completion: @escaping (_ index: Int, _ url: URL, _ offset: CMTime, _ duration: CMTime) -> Void
    ) -> DownloadSession {
        let segmentsToSkip = playlist.getSegmentsToSkipCount(startingFrom: startTime.seconds)
        
        // Telegram internal HLS server does not support stream now
        // let readOffset = playlist.segments.dropFirst(segmentsToSkip).first?.byteRange?.offset ?? 0
        
        let segmentsOffsets: [TimeInterval] = playlist.segments.reduce(into: []) { partialResult, segment in
            partialResult.append((partialResult.last ?? 0.0) + (segment.duration ?? 0))
        }
        
        let segmentsDuration: [TimeInterval] = playlist.segments.map { $0.duration ?? 0 }
        
        let downloadSession = DownloadSession(id: sessionID, resultQueue: resultQueue) { segmentIndex, fileURL in
            let offset = segmentIndex == 0 ? 0.0 : segmentsOffsets[segmentIndex - 1]
            let duration = segmentsDuration[segmentIndex]
            
            print("Loaded segment", segmentIndex)
            
            completion(segmentIndex, fileURL, CMTime(seconds: offset), CMTime(seconds: duration))
        }
        
        for (idx, segment) in playlist.segments.enumerated() {
            if idx < segmentsToSkip {
                continue
            }
            
            guard let url = try? buildURL(for: segment.uri, inStream: streamURI) else {
                continue
            }
            
            if let section = segment.initializationSection,
               let sectionURL = try? buildURL(for: section.uri, inStream: streamURI) {
                let sectionLoadMode: DownloadSession.Mode = .file(byteRange: section.byteRange)
                downloadSession.addInitializationSection(index: idx, url: sectionURL, mode: sectionLoadMode)
            }
            
            let segmentLoadMode: DownloadSession.Mode = .file(byteRange: segment.byteRange)
            downloadSession.addSegment(
                index: idx,
                url: url,
                mode: segmentLoadMode,
                initializationSection: segment.initializationSection
            )
        }
        
        return downloadSession
    }
    
    private func buildURL(for streamURI: String) throws -> URL {
        if streamURI.contains("://") {
            if let _url = URL(string: streamURI) {
                return _url
            } else {
                throw M3U8PlaylistLoaderError(message: "Invalid segment URL")
            }
        } else {
            return baseURL.appendingPathComponent(streamURI)
        }
    }
    
    private func buildURL(for segmentURI: String, inStream streamURI: String) throws -> URL {
        if segmentURI.contains("://") {
            if let _url = URL(string: segmentURI) {
                return _url
            } else {
                throw M3U8PlaylistLoaderError(message: "Invalid segment URL")
            }
        } else {
            return try buildURL(for: streamURI).deletingLastPathComponent().appendingPathComponent(segmentURI)
        }
    }
    
    private func loadMedia(playlistURL: URL, completion: @escaping (Result<M3U8.MediaPlaylist, Error>) -> Void) {
        let task = urlSession.dataTask(with: URLRequest(url: playlistURL)) { data, _, error in
            if let error {
                completion(.failure(M3U8PlaylistLoaderError(message: "Unable to load playlist: \(error)")))
                return
            }
            
            if let data {
                let parser = M3U8Parser(data: data)
                
                do {
                    let playlist = try parser.parseAsMedia()
                    completion(.success(playlist))
                } catch {
                    completion(.failure(error))
                }
            } else {
                completion(.failure(M3U8PlaylistLoaderError(message: "Unable to load playlist")))
            }
        }
        task.resume()
    }
}

struct M3U8PlaylistLoaderError: Error {
    let message: String
}

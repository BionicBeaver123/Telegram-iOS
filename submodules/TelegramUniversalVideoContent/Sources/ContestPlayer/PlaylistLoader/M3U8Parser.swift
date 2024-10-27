import Foundation

enum M3U8PlaylistKind {
    case master
    case media
}

struct M3U8Tag {
    let tag: String
    let params: [(key: String, value: String)]
}

final class M3U8Parser {
    private let data: Data
    
    private static let mediaTags = Set<String>([
        "EXTINF", "EXT-X-BYTERANGE", "EXT-X-DISCONTINUITY",
        "EXT-X-KEY", "EXT-X-MAP", "EXT-X-PROGRAM-DATE-TIME",
        "EXT-X-DATERANGE", "EXT-X-TARGETDURATION",
        "EXT-X-MEDIA-SEQUENCE", "EXT-X-DISCONTINUITY-SEQUENCE",
        "EXT-X-ENDLIST", "EXT-X-PLAYLIST-TYPE", "EXT-X-I-FRAMES-ONLY"
    ])

    init(data: Data) {
        self.data = data
    }
    
    func parseAsMedia() throws -> M3U8.MediaPlaylist {
        guard let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") else {
            throw M3U8ParserError.invalidEncoding
        }
        
        if lines.first != "#EXTM3U" {
            throw M3U8ParserError.invalidFormat("Playlist should contain #EXTM3U at first line")
        }
        
        var playlist = M3U8.MediaPlaylist()
        
        var lastInitializationSection: M3U8.MediaPlaylist.Segment.InitializationSection?
        var lastDuration: Double?
        var lastByteRange: M3U8.ByteRange?
        
        for line in lines {
            if line.starts(with: "#") {
                guard let tag = parseTag(String(line)) else {
                    throw M3U8ParserError.invalidFormat("Invalid format for tag in string \(line)")
                }

                switch tag.tag {
                case "EXT-X-MAP":
                    let initializationSection = M3U8.MediaPlaylist.Segment.InitializationSection(
                        uri: try extractParam(tag.params, "URI"),
                        byteRange: (try? extractParam(tag.params, "BYTERANGE") as String).flatMap {
                            let parts = $0.split(separator: "@")
                            if let length = parts.first.flatMap({ Int($0) }), let start = parts.last.flatMap({ Int($0) }) {
                                return M3U8.ByteRange(length: length, offset: start)
                            }
                            return nil
                        }
                    )
                    lastInitializationSection = initializationSection
                
                case "EXTINF":
                    lastDuration = try extractSingle(tag.params) as Double
                    
                case "EXT-X-BYTERANGE":
                    lastByteRange = (tag.params.first?.key).flatMap {
                        let parts = $0.split(separator: "@")
                        if let length = parts.first.flatMap({ Int($0) }), let start = parts.last.flatMap({ Int($0) }) {
                            return M3U8.ByteRange(length: length, offset: start)
                        }
                        return nil
                    }
                    
                case "EXT-X-TARGETDURATION":
                    playlist.targetDuration = try extractSingle(tag.params) as Int
                    
                case "EXT-X-MEDIA-SEQUENCE":
                    playlist.mediaSequence = try? extractSingle(tag.params) as Int
                    
                case "EXT-X-DISCONTINUITY-SEQUENCE":
                    playlist.discontinuitySequence = try? extractSingle(tag.params) as Int
                    
                case "EXT-X-ENDLIST":
                    playlist.endlist = true
                    
                case "EXT-X-PLAYLIST-TYPE":
                    playlist.playlistType = (try? extractSingle(tag.params) as String).flatMap {
                        M3U8.MediaPlaylist.PlaylistType(rawValue: $0)
                    }
                    
                case "EXT-X-I-FRAMES-ONLY":
                    playlist.hasIFramesOnly = true
                
                default:
                    continue
                }
            } else {
                let segment = M3U8.MediaPlaylist.Segment(
                    duration: lastDuration,
                    byteRange: lastByteRange,
                    uri: String(line),
                    initializationSection: lastInitializationSection
                )
                playlist.segments.append(segment)
                
                lastDuration = nil
                lastByteRange = nil
            }
        }
        
        return playlist
    }
    
    func parseAsMaster() throws -> M3U8.MasterPlaylist {
        guard let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") else {
            throw M3U8ParserError.invalidEncoding
        }
        
        if lines.first != "#EXTM3U" {
            throw M3U8ParserError.invalidFormat("Playlist should contain #EXTM3U at first line")
        }
        
        var playlist = M3U8.MasterPlaylist()
        
        var shiftedLines = lines.dropFirst()
        shiftedLines.append("")
        
        for (line, nextLine) in zip(lines, shiftedLines) {
            if line.starts(with: "#") {
                guard let tag = parseTag(String(line)) else {
                    throw M3U8ParserError.invalidFormat("Invalid format for tag in string \(line)")
                }
                
                if Self.mediaTags.contains(tag.tag) {
                    throw M3U8ParserError.mediaInsteadOfMaster
                }

                switch tag.tag {
                case "EXT-X-MEDIA":
                    let typeString = try extractParam(tag.params, "TYPE") as String
                    guard let type = M3U8.MasterPlaylist.MediaTag.MediaType(rawValue: typeString) else {
                        throw M3U8ParserError.invalidFormat("Invalid media type \(typeString)")
                    }
                    
                    let mediaTag = M3U8.MasterPlaylist.MediaTag(
                        type: type,
                        uri: try? extractParam(tag.params, "URI"),
                        groupID: try? extractParam(tag.params, "GROUP-ID"),
                        language: try? extractParam(tag.params, "LANGUAGE"),
                        assocLanguage: try? extractParam(tag.params, "ASSOC-LANGUAGE"),
                        name: try? extractParam(tag.params, "NAME"),
                        default: try? extractParam(tag.params, "DEFAULT") == "YES",
                        autoselect: try? extractParam(tag.params, "AUTOSELECT") == "YES",
                        forced: try? extractParam(tag.params, "FORCED") == "YES",
                        instreamID: try? extractParam(tag.params, "INSTREAM-ID"),
                        characteristics: try? extractParam(tag.params, "CHARACTERISTICS"),
                        channels: try? extractParam(tag.params, "CHANNELS")
                    )
                    playlist.mediaTags.append(mediaTag)
                    
                case "EXT-X-STREAM-INF":
                    let stream = M3U8.MasterPlaylist.Stream(
                        bandwidth: try? extractParam(tag.params, "BANDWIDTH") as Int,
                        averageBandwidth: try? extractParam(tag.params, "AVERAGE-BANDWIDTH") as Int,
                        codecs: try? extractParam(tag.params, "CODECS"),
                        resolution: try? extractParam(tag.params, "RESOLUTION") as M3U8.MasterPlaylist.Stream.Resolution,
                        frameRate: try? extractParam(tag.params, "FRAME-RATE"),
                        hdcpLevel: try? extractParam(tag.params, "HDCP-LEVEL"),
                        audio: try? extractParam(tag.params, "AUDIO"),
                        video: try? extractParam(tag.params, "VIDEO"),
                        subtitles: try? extractParam(tag.params, "SUBTITLES"),
                        closedCaptions: try? extractParam(tag.params, "CLOSED-CAPTIONS"),
                        uri: String(nextLine)
                    )
                    playlist.streams.append(stream)
                    
                case "EXT-X-I-FRAME-STREAM-INF":
                    let stream = M3U8.MasterPlaylist.Stream(
                        bandwidth: try? extractParam(tag.params, "BANDWIDTH") as Int,
                        averageBandwidth: try? extractParam(tag.params, "AVERAGE-BANDWIDTH") as Int,
                        codecs: try? extractParam(tag.params, "CODECS"),
                        resolution: try? extractParam(tag.params, "RESOLUTION") as M3U8.MasterPlaylist.Stream.Resolution,
                        frameRate: try? extractParam(tag.params, "FRAME-RATE"),
                        hdcpLevel: try? extractParam(tag.params, "HDCP-LEVEL"),
                        audio: try? extractParam(tag.params, "AUDIO"),
                        video: try? extractParam(tag.params, "VIDEO"),
                        subtitles: try? extractParam(tag.params, "SUBTITLES"),
                        closedCaptions: try? extractParam(tag.params, "CLOSED-CAPTIONS"),
                        uri: try extractParam(tag.params, "URI")
                    )
                    playlist.iFrameStreams.append(stream)
                    
                case "EXT-X-SESSION-DATA":
                    playlist.sessionData.append(.init(rawParams: tag.params))
                
                case "EXT-X-SESSION-KEY":
                    playlist.sessionKey.append(.init(rawParams: tag.params))
                    
                case "EXT-X-INDEPENDENT-SEGMENTS":
                    playlist.hasIndependentSegments = true
                    
                case "EXT-X-START":
                    let start = M3U8.StartPoint(
                        timeOffset: try? extractParam(tag.params, "TIME-OFFSET") as Double,
                        precise: (try? extractParam(tag.params, "AUTOSELECT") == "YES") ?? false
                    )
                    playlist.start = start
                
                default:
                    continue
                }
            } else {
                continue
            }
        }
        
        return playlist
    }
}

private func extractSingle<T: ValueTypeRepresentable>(_ params: [(key: String, value: String)]) throws -> T {
    guard let item = params.first?.key else {
        throw M3U8ParserError.invalidFormat("Required single value missed")
    }
    
    guard let castedItem = T.fromString(item) else {
        throw M3U8ParserError.invalidFormat("Invalid type cast for single value '\(item)' to '\(T.self)'")
    }
    
    return castedItem
}

private func extractParam<T: ValueTypeRepresentable>(_ params: [(key: String, value: String)], _ targetKey: String) throws -> T {
    guard let item = params.first(where: { $0.key == targetKey }) else {
        throw M3U8ParserError.invalidFormat("Required key '\(targetKey)' missed, params \(params)")
    }
    
    guard let castedItem = T.fromString(item.value) else {
        throw M3U8ParserError.invalidFormat("Invalid type cast for single value '\(item.value)' to '\(T.self)'")
    }
    
    return castedItem
}

private func parseTag(_ string: String) -> M3U8Tag? {
    if !string.starts(with: "#") {
        return nil
    }
    
    let string = string.dropFirst()
    let parts = string.split(separator: ":")
    
    guard let tag = parts.first else {
        return nil
    }
    
    let paramsString = parts.dropFirst().joined(separator: ":")
    
    var params: [(String, String)] = []
    
    var insideEscapedSeq = false
    var parseValue = false
    var paramKey = ""
    var paramValue = ""
    
    for char in (paramsString + ",") {
        if char == "\"" {
            insideEscapedSeq.toggle()
        } else if char == "=" && !insideEscapedSeq {
            parseValue = true
        } else if char == "," && !insideEscapedSeq {
            params.append((paramKey, paramValue))
            parseValue = false
            paramKey = ""
            paramValue = ""
        } else if !parseValue {
            paramKey.append(char)
        } else {
            paramValue.append(char)
        }
    }
    
    return .init(tag: .init(tag), params: params)
}

enum M3U8ParserError: Error, Equatable {
    case invalidEncoding
    case invalidFormat(String)
    case mediaInsteadOfMaster
}

protocol ValueTypeRepresentable { 
    static func fromString(_ value: String) -> Self?
}

extension Int: ValueTypeRepresentable {
    static func fromString(_ value: String) -> Int? {
        Int(value)
    }
}

extension Double: ValueTypeRepresentable {
    static func fromString(_ value: String) -> Double? {
        Double(value)
    }
}

extension String: ValueTypeRepresentable {
    static func fromString(_ value: String) -> String? {
        value
    }
}

extension M3U8.MasterPlaylist.Stream.Resolution: ValueTypeRepresentable {
    static func fromString(_ value: String) -> M3U8.MasterPlaylist.Stream.Resolution? {
        .init(value: value)
    }
}

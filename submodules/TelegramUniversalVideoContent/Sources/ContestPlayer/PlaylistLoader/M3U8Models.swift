import Foundation

// https://datatracker.ietf.org/doc/html/rfc8216
enum M3U8 {
    enum Playlist {
        case master(MasterPlaylist)
        case media(MediaPlaylist)
    }
    
    struct ByteRange {
        var length: Int
        var offset: Int
    }
    
    struct StartPoint {
        var timeOffset: Double?
        var precise: Bool
    }
    
    struct MediaPlaylist {
        var targetDuration: Int = 0
        var mediaSequence: Int?
        var discontinuitySequence: Int?
        var endlist: Bool = false
        var playlistType: PlaylistType?
        var hasIFramesOnly: Bool = false
        var segments: [Segment] = []
        
        struct Segment {
            var duration: Double?
            var byteRange: ByteRange?
            var uri: String
            var initializationSection: InitializationSection? = nil
            
            struct InitializationSection {
                var uri: String
                var byteRange: ByteRange?
            }
        }
        
        enum PlaylistType: String {
            case event = "EVENT"
            case vod = "VOD"
        }
    }
    
    struct MasterPlaylist {
        var mediaTags: [MediaTag] = []
        var streams: [Stream] = []
        var iFrameStreams: [Stream] = []
        var sessionData: [SessionData] = []
        var sessionKey: [SessionKey] = []
        var hasIndependentSegments: Bool = false
        var start: StartPoint?
        
        struct Stream {
            var bandwidth: Int?
            var averageBandwidth: Int?
            var codecs: String?
            var resolution: Resolution?
            var frameRate: String?
            var hdcpLevel: String?
            var audio: String?
            var video: String?
            var subtitles: String?
            var closedCaptions: String?
            var uri: String
            
            struct Resolution: Hashable {
                let value: String
            }
        }
        
        struct MediaTag {
            var type: MediaType = .audio
            var uri: String?
            var groupID: String?
            var language: String?
            var assocLanguage: String?
            var name: String?
            var `default`: Bool?
            var autoselect: Bool?
            var forced: Bool?
            var instreamID: String?
            var characteristics: String?
            var channels: String?
            
            enum MediaType: String {
                case audio = "AUDIO"
                case video = "VIDEO"
                case subtitles = "SUBTITLES"
                case closedCaptions = "CLOSED-CAPTIONS"
            }
        }
        
        struct SessionData {
            var rawParams: [(key: String, value: String)]
        }
        
        struct SessionKey {
            var rawParams: [(key: String, value: String)]
        }
    }
}

extension M3U8.MasterPlaylist.Stream.Resolution {
    var short: Int {
        Int(String(value.split(separator: "x").last ?? "")) ?? 0
    }
}

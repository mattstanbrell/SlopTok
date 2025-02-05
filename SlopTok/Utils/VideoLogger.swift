import Foundation

enum VideoLogEvent: String {
    case cacheHit = "CACHE_HIT"
    case cacheMiss = "CACHE_MISS"
    case cacheExpired = "CACHE_EXPIRED"
    case downloadStarted = "DOWNLOAD_STARTED"
    case downloadCompleted = "DOWNLOAD_COMPLETED"
    case downloadFailed = "DOWNLOAD_FAILED"
    case preloadStarted = "PRELOAD_STARTED"
    case preloadCompleted = "PRELOAD_COMPLETED"
    case preloadFailed = "PRELOAD_FAILED"
    case likesLoaded = "LIKES_LOADED"
    case playerCreated = "PLAYER_CREATED"
    case playerPrepared = "PLAYER_PREPARED"
    case playerFailed = "PLAYER_FAILED"
    case playerStarted = "PLAYER_STARTED"
    case playerPaused = "PLAYER_PAUSED"
}

class VideoLogger {
    static let shared = VideoLogger()
    private init() {}
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    func log(_ event: VideoLogEvent, videoId: String, message: String? = nil, error: Error? = nil) {
        let timestamp = dateFormatter.string(from: Date())
        var logMessage = "[\(timestamp)] [\(event.rawValue)] Video[\(videoId)]"
        if let message = message {
            logMessage += " - \(message)"
        }
        if let error = error {
            logMessage += " Error: \(error.localizedDescription)"
        }
        print(logMessage)
    }
}

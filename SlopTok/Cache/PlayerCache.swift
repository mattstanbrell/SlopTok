import AVKit

class CachedPlayer {
    let player: AVPlayer
    let videoId: String
    var isPrevious: Bool = false
    
    init(player: AVPlayer, videoId: String) {
        self.player = player
        self.videoId = videoId
        
        // Set up loop behavior
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}

class PlayerCache {
    static let shared = PlayerCache()
    private let cache = NSCache<NSString, CachedPlayer>()
    private var currentVideoId: String?
    private var previousVideoId: String?
    
    private init() {
        cache.countLimit = 10  // More than enough for our 4 videos
    }
    
    func updatePosition(current: String) {
        if current != currentVideoId {
            previousVideoId = currentVideoId
            if let previous = previousVideoId,
               let player = cache.object(forKey: previous as NSString) {
                player.isPrevious = true
            }
            currentVideoId = current
            
            // Update video file LRU without checking cache again
            if let localURL = try? FileManager.default.destinationOfSymbolicLink(atPath: VideoFileCache.shared.localFileURL(for: current).path) {
                VideoFileCache.shared.updateLRUPosition(current)
            }
        }
    }
    
    // Check if player exists without logging
    func hasPlayer(for videoId: String) -> Bool {
        return cache.object(forKey: videoId as NSString)?.player != nil
    }
    
    func getPlayer(for videoId: String) -> AVPlayer? {
        let player = cache.object(forKey: videoId as NSString)?.player
        if player != nil {
            VideoLogger.shared.log(.cacheHit, videoId: videoId, message: "Found player in cache")
        }
        return player
    }
    
    func setPlayer(_ player: AVPlayer, for videoId: String) {
        let cachedPlayer = CachedPlayer(player: player, videoId: videoId)
        cache.setObject(cachedPlayer, forKey: videoId as NSString)
    }
    
    // With only 4 videos, we don't need to remove any players from cache
    func removePlayer(for videoId: String) {
        // No-op - we keep all players in cache since we have plenty of space
    }
    
    // Get all cached video IDs for debugging
    func getCachedVideoIds() -> [String] {
        var ids: [String] = []
        // Enumerate cache contents (NSCache doesn't provide direct access)
        for key in (0...100) { // arbitrary upper limit
            let keyString = String(key)
            if cache.object(forKey: keyString as NSString) != nil {
                ids.append(keyString)
            }
        }
        return ids
    }
}

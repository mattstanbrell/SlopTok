import AVKit
import os

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
    private let logger = Logger(subsystem: "com.sloptok", category: "PlayerCache")
    
    // Track cached video IDs since NSCache doesn't provide enumeration
    private var cachedVideoIds: Set<String> = []
    private let maxPlayers = 10
    
    private init() {
        cache.countLimit = self.maxPlayers
        logger.info("PlayerCache initialized with limit of \(self.maxPlayers) players")
    }
    
    func updatePosition(current: String) {
        logger.info("🔄 Updating position - Current: \(current), Previous: \(self.currentVideoId ?? "none")")
        
        if current != currentVideoId {
            previousVideoId = currentVideoId
            if let previous = previousVideoId,
               let player = cache.object(forKey: previous as NSString) {
                player.isPrevious = true
                logger.info("📍 Marked player as previous: \(previous)")
            }
            currentVideoId = current
            logger.info("✅ Updated current video to: \(current)")
            
            // Update video file LRU without checking cache again
            if let localURL = try? FileManager.default.destinationOfSymbolicLink(atPath: VideoFileCache.shared.localFileURL(for: current).path) {
                VideoFileCache.shared.updateLRUPosition(current)
                logger.info("📝 Updated LRU position for video: \(current)")
            }
        }
    }
    
    func hasPlayer(for videoId: String) -> Bool {
        let exists = cache.object(forKey: videoId as NSString)?.player != nil
        logger.info("\(exists ? "✅" : "❌") [AVPlayer Cache] \(exists ? "Found" : "Not found") for video: \(videoId)")
        return exists
    }
    
    func getPlayer(for videoId: String) -> AVPlayer? {
        if let player = cache.object(forKey: videoId as NSString)?.player {
            logger.info("✅ [AVPlayer Cache] Retrieved player for video: \(videoId)")
            return player
        }
        logger.info("❌ [AVPlayer Cache] No player found for video: \(videoId)")
        return nil
    }
    
    func setPlayer(_ player: AVPlayer, for videoId: String) {
        logger.info("➕ [AVPlayer Cache] Creating new player for video: \(videoId)")
        let cachedPlayer = CachedPlayer(player: player, videoId: videoId)
        
        // If we're at capacity, remove oldest non-current/previous player
        if cachedVideoIds.count >= maxPlayers {
            let candidatesForRemoval = cachedVideoIds.filter { id in
                id != currentVideoId && id != previousVideoId
            }
            
            if let oldestId = candidatesForRemoval.first {
                removePlayer(for: oldestId)
                logger.info("🗑️ [AVPlayer Cache] Removed oldest player for video: \(oldestId)")
            }
        }
        
        cache.setObject(cachedPlayer, forKey: videoId as NSString)
        cachedVideoIds.insert(videoId)
        
        // Log cache state
        logger.info("📊 [AVPlayer Cache] Current state - Total players: \(self.cachedVideoIds.count), Active players: \(self.cachedVideoIds.joined(separator: ", "))")
    }
    
    func removePlayer(for videoId: String) {
        // Only remove if it's not the current or previous video
        if videoId != currentVideoId && videoId != previousVideoId {
            cache.removeObject(forKey: videoId as NSString)
            cachedVideoIds.remove(videoId)
            logger.info("🗑️ [AVPlayer Cache] Removed player for video: \(videoId)")
        } else {
            logger.info("ℹ️ [AVPlayer Cache] Keeping player in cache for current/previous video: \(videoId)")
        }
    }
    
    func getCachedVideoIds() -> [String] {
        return Array(cachedVideoIds)
    }
}
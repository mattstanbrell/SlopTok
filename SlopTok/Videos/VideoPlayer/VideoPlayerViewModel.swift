import SwiftUI
import AVKit

class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var showPlayPauseIcon = false
    @Published var showHeartIcon = false
    @Published var heartOpacity = 0.0
    @Published var heartColor = Color.white
    
    private let videoResource: String
    private let likesService: LikesService
    private var isVideoLiked: Binding<Bool>
    
    init(videoResource: String, likesService: LikesService, isVideoLiked: Binding<Bool>) {
        self.videoResource = videoResource
        self.likesService = likesService
        self.isVideoLiked = isVideoLiked
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VideoPlayerCellStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isActive = notification.userInfo?["isActive"] as? Bool,
                  let videoId = notification.userInfo?["videoId"] as? String,
                  videoId == self.videoResource else {
                return
            }
            
            if isActive {
                self.setupPlayer()
                self.updatePlayback(isActive: true)
            } else {
                self.updatePlayback(isActive: false)
                self.player = nil
            }
        }
    }
    
    func setupPlayer() {
        if player == nil {
            // First check if we have a preloaded player
            if let preloadedPlayer = PlayerCache.shared.getPlayer(for: videoResource) {
                VideoLogger.shared.log(.playerStarted, videoId: videoResource, message: "Using preloaded player")
                self.player = preloadedPlayer
                return  // Don't remove from cache, we'll reuse it
            }
            
            // If no preloaded player, check file cache
            let localURL = VideoFileCache.shared.localFileURL(for: videoResource)
            if FileManager.default.fileExists(atPath: localURL.path) {
                VideoLogger.shared.log(.cacheHit, videoId: videoResource, message: "Found cached video file")
                createPlayer(with: localURL)
                return
            }
            
            // Last resort: download the video
            VideoLogger.shared.log(.cacheMiss, videoId: videoResource, message: "Video not cached, downloading")
            VideoURLCache.shared.getVideoURL(for: videoResource) { [weak self] remoteURL in
                guard let self = self, let remoteURL = remoteURL else {
                    VideoLogger.shared.log(.downloadFailed, videoId: self?.videoResource ?? "", message: "Failed to get video URL")
                    return
                }
                
                VideoFileCache.shared.getLocalVideoURL(for: self.videoResource, remoteURL: remoteURL) { localURL in
                    guard let localURL = localURL else {
                        VideoLogger.shared.log(.downloadFailed, videoId: self.videoResource, message: "Failed to get local URL")
                        return
                    }
                    DispatchQueue.main.async {
                        self.createPlayer(with: localURL)
                    }
                }
            }
        }
    }
    
    private func createPlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = .none
        self.player = newPlayer
        VideoLogger.shared.log(.playerCreated, videoId: videoResource, message: "Created new player")
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            newPlayer.seek(to: .zero)
            if self?.isPlaying == true {
                newPlayer.play()
            }
        }
    }
    
    func handleSingleTap() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        
        showPlayPauseIcon = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showPlayPauseIcon = false
        }
    }
    
    func handleDoubleTap() {
        Task { @MainActor in
            if isVideoLiked.wrappedValue {
                likesService.toggleLike(videoId: videoResource)
                isVideoLiked.wrappedValue = false
                heartColor = .white
            } else {
                likesService.toggleLike(videoId: videoResource)
                isVideoLiked.wrappedValue = true
                heartColor = .red
            }
            
            showHeartIcon = true
            heartOpacity = 1.0
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            withAnimation {
                heartOpacity = 0.0
            }
        }
    }
    
    func updatePlayback(isActive: Bool) {
        if isActive {
            player?.seek(to: .zero)
            player?.play()
            isPlaying = true
            VideoLogger.shared.log(.playerStarted, videoId: videoResource, message: "Player started")
        } else {
            player?.pause()
            player?.seek(to: .zero)
            isPlaying = false
            VideoLogger.shared.log(.playerPaused, videoId: videoResource, message: "Player paused")
        }
    }
}

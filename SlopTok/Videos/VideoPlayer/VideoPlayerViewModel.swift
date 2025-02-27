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
    
    func setupPlayer(completion: (() -> Void)? = nil) {
        if player == nil {
            // First check if we have a preloaded player
            if let preloadedPlayer = PlayerCache.shared.getPlayer(for: videoResource) {
                self.player = preloadedPlayer
                completion?()
                return
            }
            
            // Last resort: download the video
            VideoURLCache.shared.getVideoURL(for: videoResource) { [weak self] remoteURL in
                guard let self = self, let remoteURL = remoteURL else { return }
                
                VideoFileCache.shared.getLocalVideoURL(for: self.videoResource, remoteURL: remoteURL) { localURL in
                    guard let localURL = localURL else { return }
                    DispatchQueue.main.async {
                        self.createPlayer(with: localURL)
                        PlayerCache.shared.setPlayer(self.player!, for: self.videoResource)
                        completion?()
                    }
                }
            }
        } else {
            completion?()
        }
    }
    
    private func createPlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = .none
        self.player = newPlayer
        
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
            
            // Mark video as seen when it becomes active
            Task {
                await VideoViewService.shared.markVideoSeen(videoId: videoResource)
            }
        } else {
            player?.pause()
            player?.seek(to: .zero)
            isPlaying = false
        }
    }
}
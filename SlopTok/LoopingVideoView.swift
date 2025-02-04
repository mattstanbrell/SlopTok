import SwiftUI
import AVKit

struct LoopingVideoView: View {
    let videoResource: String
    var onDoubleTapAction: (() -> Void)? = nil
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var wasUserPaused = false
    @State private var showPlayPauseIcon = false
    @State private var showHeartIcon = false
    @State private var heartOpacity = 0.0
    @State private var heartColor = Color.white
    @ObservedObject var likesService: LikesService
    @Binding var isVideoLiked: Bool
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(
                        Color.black.opacity(0.01)
                            .allowsHitTesting(true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleSingleTap(player)
                            }
                            .onTapGesture(count: 2) {
                                handleDoubleTap()
                            }
                    )
            } else {
                Color.black.ignoresSafeArea()
            }
            
            if showPlayPauseIcon {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            
            Image(systemName: "heart.fill")
                .font(.system(size: 75))
                .foregroundColor(heartColor)
                .opacity(heartOpacity)
                .animation(.easeOut(duration: 0.2), value: heartColor)
        }
        .onAppear {
            setupPlayer()
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        let frame = geometry.frame(in: .global)
                        let screen = UIScreen.main.bounds
                        let isActive = abs(frame.midY - screen.midY) < 50
                        updatePlayback(isActive: isActive)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        let screen = UIScreen.main.bounds
                        let isActive = abs(newFrame.midY - screen.midY) < 50
                        updatePlayback(isActive: isActive)
                    }
            }
        )
    }
    
    private func setupPlayer() {
        if player == nil {
            if let url = Bundle.main.url(forResource: videoResource, withExtension: "mp4") {
                let playerItem = AVPlayerItem(url: url)
                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.automaticallyWaitsToMinimizeStalling = false
                newPlayer.actionAtItemEnd = .none
                
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: newPlayer.currentItem,
                    queue: .main
                ) { _ in
                    newPlayer.seek(to: .zero)
                    if isPlaying {
                        newPlayer.play()
                    }
                }
                player = newPlayer
            }
        }
    }
    
    private func handleSingleTap(_ player: AVPlayer) {
        if isPlaying {
            player.pause()
            isPlaying = false
            wasUserPaused = true
        } else {
            player.play()
            isPlaying = true
            wasUserPaused = false
        }
        
        withAnimation(.easeIn(duration: 0.2)) {
            showPlayPauseIcon = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showPlayPauseIcon = false
            }
        }
    }
    
    private func handleDoubleTap() {
        if let action = onDoubleTapAction {
            action()
        } else {
            let isCurrentlyLiked = likesService.isLiked(videoId: videoResource)
            likesService.toggleLike(videoId: videoResource)
            isVideoLiked.toggle()
            
            heartColor = isCurrentlyLiked ? .white : .red
            
            withAnimation(.easeIn(duration: 0.1)) {
                heartOpacity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    heartOpacity = 0.0
                }
            }
        }
    }
    
    private func updatePlayback(isActive: Bool) {
        guard let player = player else { return }
        if isActive {
            if !isPlaying {
                if wasUserPaused {
                    player.play()
                } else {
                    player.seek(to: .zero)
                    player.play()
                }
                isPlaying = true
            }
        } else {
            if isPlaying {
                player.pause()
                if !wasUserPaused {
                    player.seek(to: .zero)
                }
                isPlaying = false
            }
        }
    }
}
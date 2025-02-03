import SwiftUI
import AVKit

struct LoopingVideoView: View {
    let videoResource: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var wasUserPaused = false
    @State private var showPlayPauseIcon = false

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.01))
                    .onTapGesture {
                        // Toggle play/pause on tap
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
            } else {
                Color.black.ignoresSafeArea()
            }
            
            if showPlayPauseIcon {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color.white.opacity(0.8))
            }
        }
        .onAppear {
            // Initialize the player if not already set
            if player == nil {
                if let url = Bundle.main.url(forResource: videoResource, withExtension: "mp4") {
                    let playerItem = AVPlayerItem(url: url)
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    // Reduce delay for playback
                    newPlayer.automaticallyWaitsToMinimizeStalling = false
                    newPlayer.actionAtItemEnd = .none
                    
                    // Loop the video
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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        let frame = geometry.frame(in: .global)
                        let screen = UIScreen.main.bounds
                        // Check if the view's center is within 50 points of the screen's center
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
    
    private func updatePlayback(isActive: Bool) {
        guard let player = player else { return }
        if isActive {
            // When active, if not already playing, start or resume playback.
            if !isPlaying {
                if wasUserPaused {
                    player.play() // Resume from paused position
                } else {
                    player.seek(to: .zero) // Start from beginning
                    player.play()
                }
                isPlaying = true
            }
        } else {
            // When not active, pause the video.
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

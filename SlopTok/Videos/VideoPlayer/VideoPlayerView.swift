import SwiftUI
import AVKit
import FirebaseStorage

struct VideoPlayerView: View {
    let videoResource: String
    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var previousMidY: CGFloat = 0

    init(videoResource: String, likesService: LikesService, isVideoLiked: Binding<Bool>) {
        self.videoResource = videoResource
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(
            videoResource: videoResource,
            likesService: likesService,
            isVideoLiked: isVideoLiked
        ))
    }
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(
                        Color.black.opacity(0.01)
                            .allowsHitTesting(true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.handleSingleTap()
                            }
                            .onTapGesture(count: 2) {
                                viewModel.handleDoubleTap()
                            }
                    )
            } else {
                Color.black.ignoresSafeArea()
            }
            
            if viewModel.showPlayPauseIcon {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            
            Image(systemName: "heart.fill")
                .font(.system(size: 75))
                .foregroundColor(viewModel.heartColor)
                .opacity(viewModel.heartOpacity)
                .animation(.easeOut(duration: 0.2), value: viewModel.heartColor)
        }
        .onAppear {
            viewModel.setupPlayer {
                viewModel.updatePlayback(isActive: true)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        let frame = geometry.frame(in: .global)
                        let screen = UIScreen.main.bounds
                        previousMidY = frame.midY
                        let isActive = abs(frame.midY - screen.midY) < 50
                        viewModel.updatePlayback(isActive: isActive)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        let screen = UIScreen.main.bounds
                        if abs(newFrame.midY - previousMidY) > 50 {
                            let isActive = abs(newFrame.midY - screen.midY) < 50
                            viewModel.updatePlayback(isActive: isActive)
                            previousMidY = newFrame.midY
                        }
                    }
            }
        )
    }
}
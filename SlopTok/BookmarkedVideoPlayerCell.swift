import SwiftUI
import AVKit

struct BookmarkedVideoPlayerCell: View {
    let video: VideoPlayerData
    let isCurrentVideo: Bool
    let onUnbookmark: () -> Void
    let likesService: LikesService
    
    var body: some View {
        ZStack {
            LoopingVideoView(
                videoResource: video.id,
                onDoubleTapAction: {
                    onUnbookmark()
                },
                likesService: likesService,
                isVideoLiked: .constant(true)
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
} 
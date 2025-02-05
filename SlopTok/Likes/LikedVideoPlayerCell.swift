import SwiftUI
import AVKit

struct LikedVideoPlayerCell: View {
    let video: VideoPlayerModel
    let isCurrentVideo: Bool
    let onUnlike: () -> Void
    @ObservedObject var likesService: LikesService
    
    var body: some View {
        ZStack {
            VideoPlayerView(
                videoResource: video.id,
                likesService: likesService,
                isVideoLiked: .constant(true),  // Always true in liked videos view
                onDoubleTapAction: onUnlike
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
}

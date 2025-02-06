import SwiftUI
import AVKit
// Updated struct declaration without onUnlike callback
struct LikedVideoPlayerCell: View {
    let video: VideoPlayerModel
    let isCurrentVideo: Bool
    @ObservedObject var likesService: LikesService
    
    var body: some View {
        ZStack {
            VideoPlayerView(
                videoResource: video.id,
                likesService: likesService,
                isVideoLiked: Binding(
                    get: { likesService.isLiked(videoId: video.id) },
                    set: { _ in }
                )
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
}
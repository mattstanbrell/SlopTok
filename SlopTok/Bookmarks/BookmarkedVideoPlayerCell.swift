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
                likesService: likesService,
                isVideoLiked: Binding(
                    get: { likesService.isLiked(videoId: video.id) },
                    set: { _ in likesService.toggleLike(videoId: video.id) }
                )
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
} 
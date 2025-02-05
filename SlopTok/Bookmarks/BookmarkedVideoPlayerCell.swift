import SwiftUI

struct BookmarkedVideoPlayerCell: View {
    let video: VideoPlayerModel
    let isCurrentVideo: Bool
    let onUnbookmark: () -> Void
    @ObservedObject var likesService: LikesService
    
    var body: some View {
        ZStack {
            VideoPlayerView(
                videoResource: video.id,
                likesService: likesService,
                isVideoLiked: Binding(
                    get: { likesService.isLiked(videoId: video.id) },
                    set: { _ in }
                ),
                onDoubleTapAction: onUnbookmark
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
}
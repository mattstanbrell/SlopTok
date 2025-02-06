import SwiftUI
import AVKit

protocol SavedVideoPlayerCell: View {
    var video: VideoPlayerModel { get }
    var isCurrentVideo: Bool { get }
    var likesService: LikesService { get }
}

extension SavedVideoPlayerCell {
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

struct DefaultSavedVideoPlayerCell: SavedVideoPlayerCell {
    let video: VideoPlayerModel
    let isCurrentVideo: Bool
    @ObservedObject var likesService: LikesService
}

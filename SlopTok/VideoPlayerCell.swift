import SwiftUI
import AVKit

struct VideoPlayerCell: View {
    let video: VideoPlayerData
    let isCurrentVideo: Bool
    let onUnlike: () -> Void
    let likesService: LikesService
    
    var body: some View {
        ZStack {
            LoopingVideoView(
                videoResource: video.id,
                likesService: likesService,
                isVideoLiked: Binding(
                    get: { true },
                    set: { _ in onUnlike() }
                )
            )
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped()
    }
}

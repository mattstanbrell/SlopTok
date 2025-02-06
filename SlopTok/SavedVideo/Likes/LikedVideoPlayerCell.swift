import SwiftUI
import AVKit

struct LikedVideoPlayerCell: SavedVideoPlayerCellFactory {
    @MainActor
    static func create(video: VideoPlayerModel, isCurrentVideo: Bool, service: LikesService) async -> AnyView {
        AnyView(
            DefaultSavedVideoPlayerCell(
                video: video,
                isCurrentVideo: isCurrentVideo,
                likesService: service
            )
        )
    }
}
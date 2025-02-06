import SwiftUI
import AVKit

struct BookmarkedVideoPlayerCell: SavedVideoPlayerCellFactory {
    @MainActor
    static func create(video: VideoPlayerModel, isCurrentVideo: Bool, service: BookmarksService) async -> AnyView {
        let likesService = LikesService()
        return AnyView(
            DefaultSavedVideoPlayerCell(
                video: video,
                isCurrentVideo: isCurrentVideo,
                likesService: likesService
            )
        )
    }
}
import SwiftUI
import FirebaseAuth

struct UserVideoPlayerView: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed in
    @StateObject private var likesService = LikesService()
    @StateObject private var bookmarksService = BookmarksService()
    
    // Configuration
    let initialIndex: Int
    
    // Local state
    @State private var videos: [VideoPlayerModel]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false
    
    init(userVideos: [UserVideo], initialIndex: Int) {
        self.initialIndex = initialIndex
        
        // Create initial video data with indices
        let videoData = userVideos.enumerated().map { index, video in
            VideoPlayerModel(id: video.id, timestamp: video.timestamp, index: index)
        }
        
        // Initialize state
        _videos = State(initialValue: videoData)
        _currentIndex = State(initialValue: initialIndex)
    }
    
    private func preloadNextVideos(from index: Int) {
        let total = videos.count
        let maxIndex = min(index + 5, total - 1)
        if maxIndex <= index { return }
        
        // Preload current video's comments
        CommentsService.shared.preloadComments(for: videos[index].id)
        
        for i in (index + 1)...maxIndex {
            let video = videos[i]
            VideoURLCache.shared.getVideoURL(for: video.id) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: video.id, remoteURL: url) { _ in
                        // Preloaded video file.
                    }
                }
            }
        }
    }
    
    var body: some View {
        RemovableVideoFeed(
            initialIndex: initialIndex,
            handleRemovalLocally: true,
            videos: $videos,
            currentIndex: $currentIndex,
            isDotExpanded: $isDotExpanded,
            onRemove: { video in
                Task {
                    await UserVideoService.shared.removeVideo(video.id)
                }
            },
            buildVideoCell: { video, isCurrent, onRemove in
                AnyView(
                    VideoPlayerCell(
                        video: video,
                        isCurrentVideo: isCurrent,
                        likesService: likesService
                    )
                )
            },
            buildControlDot: {
                AnyView(
                    ControlDotView(
                        isExpanded: $isDotExpanded,
                        userName: Auth.auth().currentUser?.displayName ?? "User",
                        dotColor: likesService.isLiked(videoId: videos[currentIndex].id) ? .red : .white,
                        likesService: likesService,
                        bookmarksService: bookmarksService,
                        currentVideoId: videos[currentIndex].id,
                        onBookmarkAction: nil,
                        onProfileAction: { dismiss() }
                    )
                )
            }
        )
        .task {
            await likesService.loadLikedVideos()
            await bookmarksService.loadBookmarkedVideos()
            // Start preloading from the first video immediately
            preloadNextVideos(from: currentIndex)
        }
    }
}

struct VideoPlayerCell: View {
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
import SwiftUI
import FirebaseAuth

struct BookmarkedVideoPlayerView: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed in
    let bookmarksService: BookmarksService
    @StateObject private var likesService = LikesService()
    
    // Configuration
    let initialIndex: Int
    
    // Local state
    @State private var videos: [VideoPlayerModel]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false
    
    init(bookmarkedVideos: [BookmarkedVideo], initialIndex: Int, bookmarksService: BookmarksService) {
        self.bookmarksService = bookmarksService
        self.initialIndex = initialIndex
        
        // Create initial video data with indices
        let videoData = bookmarkedVideos.enumerated().map { index, video in
            VideoPlayerModel(id: video.id, timestamp: video.timestamp, index: index)
        }
        
        // Initialize state
        _videos = State(initialValue: videoData)
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var currentVideo: VideoPlayerModel? {
        guard currentIndex >= 0 && currentIndex < videos.count else { return nil }
        return videos[currentIndex]
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
                bookmarksService.toggleBookmark(videoId: video.id)
            },
            buildVideoCell: { video, isCurrent, onRemove in
                AnyView(
                    BookmarkedVideoPlayerCell(
                        video: video,
                        isCurrentVideo: isCurrent,
                        onUnlike: onRemove,
                        likesService: likesService
                    )
                )
            },
            buildControlDot: {
                AnyView(
                    ControlDotView(
                        isExpanded: $isDotExpanded,
                        userName: Auth.auth().currentUser?.displayName ?? "User",
                        dotColor: likesService.isLiked(videoId: currentVideo?.id ?? "") ? .red : .white,
                        likesService: likesService,
                        bookmarksService: bookmarksService,
                        currentVideoId: currentVideo?.id ?? "",
                        onBookmarkAction: {
                            if let video = currentVideo {
                                bookmarksService.toggleBookmark(videoId: video.id)
                            }
                        },
                        onProfileAction: { dismiss() }
                    )
                )
            }
        )
        .task {
            await likesService.loadLikedVideos()
            // Start preloading from the first video immediately
            preloadNextVideos(from: currentIndex)
        }
        .onChange(of: bookmarksService.bookmarkedVideos) { newBookmarks in
            let newData = newBookmarks.enumerated().map { index, bookmark in
                VideoPlayerModel(id: bookmark.id, timestamp: bookmark.timestamp, index: index)
            }
            withAnimation(.easeInOut) {
                videos = newData
                if videos.isEmpty {
                    currentIndex = 0
                    dismiss()
                } else if currentIndex >= videos.count {
                    currentIndex = max(0, videos.count - 1)
                }
            }
        }
        .onChange(of: currentIndex) { newIndex in
            if newIndex < videos.count {
                preloadNextVideos(from: newIndex)
            }
        }
    }
}

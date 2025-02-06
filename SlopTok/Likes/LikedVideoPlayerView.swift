import SwiftUI
import FirebaseAuth

struct LikedVideoPlayerView: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed in
    let likesService: LikesService
    @StateObject private var bookmarksService = BookmarksService()
    
    // Configuration
    let initialIndex: Int
    
    // Local state
    @State private var videos: [VideoPlayerModel]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false
    
    init(likedVideos: [LikedVideo], initialIndex: Int, likesService: LikesService) {
        self.likesService = likesService
        self.initialIndex = initialIndex
        
        // Create initial video data with indices
        let videoData = likedVideos.enumerated().map { index, video in
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
                likesService.toggleLike(videoId: video.id)
            },
            buildVideoCell: { video, isCurrent, onRemove in
                AnyView(
                    LikedVideoPlayerCell(
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
                        dotColor: .red,
                        likesService: likesService,
                        bookmarksService: bookmarksService,
                        currentVideoId: currentVideo?.id ?? "",
                        onBookmarkAction: nil,
                        onProfileAction: { dismiss() }
                    )
                )
            }
        )
        .task {
            await bookmarksService.loadBookmarkedVideos()
            // Start preloading from the first video immediately
            preloadNextVideos(from: currentIndex)
        }
        .onChange(of: likesService.likedVideos) { newLikes in
            print("🎬 [LikedVideoPlayerView] Likes changed - New count: \(newLikes.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let newData = newLikes.enumerated().map { index, like in
                    VideoPlayerModel(id: like.id, timestamp: like.timestamp, index: index)
                }
                print("🎬 [LikedVideoPlayerView] Created new video data with \(newData.count) videos (after delay)")
                withAnimation(.easeInOut) {
                    let oldCount = videos.count
                    let oldIndex = currentIndex
                    videos = newData
                    print("🎬 [LikedVideoPlayerView] State update - Old count: \(oldCount), New count: \(videos.count), Old index: \(oldIndex), Current index: \(currentIndex)")
                    if videos.isEmpty {
                        currentIndex = 0
                        dismiss()
                    } else if currentIndex >= videos.count {
                        currentIndex = max(0, videos.count - 1)
                    } else if let current = currentVideo, videos.first?.id != current.id {
                        // If the most recent (top) liked video has been removed,
                        // animate scrolling to the new top video.
                        currentIndex = 0
                    }
                }
            }
        }
        .onChange(of: currentIndex) { newIndex in
            if newIndex < videos.count {
                preloadNextVideos(from: newIndex)
            }
        }
    }
    
    var currentVideo: VideoPlayerModel? {
        videos.first { $0.index == currentIndex }
    }
}

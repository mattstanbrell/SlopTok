import SwiftUI
import FirebaseAuth
import AVKit

protocol SavedVideoPlayerCellFactory {
    associatedtype VideoService
    @MainActor
    static func create(video: VideoPlayerModel, isCurrentVideo: Bool, service: VideoService) async -> AnyView
}

struct SavedVideoPlayerView<T: SavedVideo, Service: SavedVideoService<T>, Cell: SavedVideoPlayerCellFactory>: View where Cell.VideoService == Service {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed in
    let savedVideoService: Service
    let likesService: LikesService
    let bookmarksService: BookmarksService
    
    // Configuration
    let initialIndex: Int
    let dotColor: Color
    let onBookmarkAction: (() -> Void)?
    
    // Local state
    @State private var videos: [VideoPlayerModel]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false
    
    init(
        savedVideos: [T],
        initialIndex: Int,
        savedVideoService: Service,
        likesService: LikesService,
        bookmarksService: BookmarksService,
        dotColor: Color,
        onBookmarkAction: (() -> Void)?
    ) {
        self.savedVideoService = savedVideoService
        self.initialIndex = initialIndex
        self.dotColor = dotColor
        self.onBookmarkAction = onBookmarkAction
        self.likesService = likesService
        self.bookmarksService = bookmarksService
        
        // Create initial video data with indices
        let videoData = savedVideos.enumerated().map { index, video in
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
                savedVideoService.toggleSavedState(videoId: video.id)
            },
            buildVideoCell: { video, isCurrent, onRemove in
                AnyView(
                    AsyncView {
                        await Cell.create(video: video, isCurrentVideo: isCurrent, service: savedVideoService)
                    }
                )
            },
            buildControlDot: {
                AnyView(
                    ControlDotView(
                        isExpanded: $isDotExpanded,
                        userName: Auth.auth().currentUser?.displayName ?? "User",
                        dotColor: dotColor,
                        likesService: likesService,
                        bookmarksService: bookmarksService,
                        currentVideoId: currentVideo?.id ?? "",
                        onBookmarkAction: onBookmarkAction,
                        onProfileAction: { dismiss() }
                    )
                )
            }
        )
        .task {
            if savedVideoService is BookmarksService {
                await likesService.loadLikedVideos()
            } else {
                await bookmarksService.loadBookmarkedVideos()
            }
            // Start preloading from the first video immediately
            preloadNextVideos(from: currentIndex)
        }
        .onChange(of: savedVideoService.videos) { newVideos in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let newData = newVideos.enumerated().map { index, video in
                    VideoPlayerModel(id: video.id, timestamp: video.timestamp, index: index)
                }
                withAnimation(.easeInOut) {
                    let oldCount = videos.count
                    let oldIndex = currentIndex
                    videos = newData
                    
                    if videos.isEmpty {
                        currentIndex = 0
                        dismiss()
                    } else if currentIndex >= videos.count {
                        currentIndex = max(0, videos.count - 1)
                    } else if savedVideoService is LikesService,
                              let current = currentVideo,
                              videos.first?.id != current.id {
                        // If this is LikesService and the most recent (top) liked video has been removed,
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
}

struct AsyncView<Content: View>: View {
    let content: () async -> Content
    
    var body: some View {
        AsyncContentView(content: content)
    }
}

private struct AsyncContentView<Content: View>: View {
    let content: () async -> Content
    @State private var loadedView: Content?
    
    var body: some View {
        ZStack {
            if let loadedView = loadedView {
                loadedView
            } else {
                Color.clear
                    .task {
                        loadedView = await content()
                    }
            }
        }
    }
}

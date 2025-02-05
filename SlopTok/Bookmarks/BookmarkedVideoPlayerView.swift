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

    var body: some View {
        ZStack(alignment: .bottom) {
            RemovableVideoFeed(
                initialIndex: initialIndex,
                handleRemovalLocally: false,  // Let onChange handler manage state
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
                            onUnbookmark: onRemove,
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
            }
            .onChange(of: bookmarksService.bookmarkedVideos) { newBookmarks in
                let newData = newBookmarks.enumerated().map { index, bookmark in
                    VideoPlayerModel(id: bookmark.id, timestamp: bookmark.timestamp, index: index)
                }
                withAnimation(.easeInOut) {
                    videos = newData
                    if videos.isEmpty {
                        currentIndex = 0
                    } else if currentIndex >= videos.count {
                        currentIndex = max(0, videos.count - 1)
                    } else if let current = currentVideo, videos.first?.id != current.id {
                        // If the most recent (top) bookmarked video has been removed,
                        // animate scrolling to the new top video.
                        currentIndex = 0
                    }
                }
            }
            .onChange(of: currentIndex) { newIndex in
                if newIndex < videos.count {
                    preloadNextVideos(from: newIndex)
                }
            }
            .task {
                // Start preloading from the first video immediately
                preloadNextVideos(from: currentIndex)
            }
        }
    }

    var currentVideo: VideoPlayerModel? {
        videos.first { $0.index == currentIndex }
    }

    private func handleUnbookmark(_ video: VideoPlayerModel) {
        // Simply toggle the bookmark in Firestore; the onChange handler will update the local state.
        bookmarksService.toggleBookmark(videoId: video.id)
    }

    private func preloadNextVideos(from index: Int) {
        let total = videos.count
        let maxIndex = min(index + 5, total - 1)
        if maxIndex <= index { return }
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
}
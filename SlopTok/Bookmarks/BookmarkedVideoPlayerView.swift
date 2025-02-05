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
    @State private var videos: [VideoPlayerData]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false

    init(bookmarkedVideos: [BookmarkedVideo], initialIndex: Int, bookmarksService: BookmarksService) {
        self.bookmarksService = bookmarksService
        self.initialIndex = initialIndex

        // Create initial video data with indices
        let videoData = bookmarkedVideos.enumerated().map { index, video in
            VideoPlayerData(id: video.id, timestamp: video.timestamp, index: index)
        }

        // Initialize state
        _videos = State(initialValue: videoData)
        _currentIndex = State(initialValue: initialIndex)
    }

    var currentVideo: VideoPlayerData? {
        videos.first { $0.index == currentIndex }
    }

    var body: some View {
        Group {
            if videos.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                videoPlayerView
            }
        }
        .task {
            await likesService.loadLikedVideos()
        }
        .onChange(of: bookmarksService.bookmarkedVideos) { newBookmarks in
            let newData = newBookmarks.enumerated().map { index, bookmark in
                VideoPlayerData(id: bookmark.id, timestamp: bookmark.timestamp, index: index)
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
    }

    private var videoPlayerView: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(videos, id: \.id) { video in
                            ZStack {
                                BookmarkedVideoPlayerCell(
                                    video: video,
                                    isCurrentVideo: video.index == currentIndex,
                                    onUnbookmark: { handleUnbookmark(video) },
                                    likesService: likesService
                                )
                                if isDotExpanded {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                isDotExpanded = false
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea()
                .onAppear {
                    if currentIndex < videos.count {
                        proxy.scrollTo(videos[currentIndex].id, anchor: .center)
                    }
                }
                .onChange(of: currentIndex) { newIndex in
                    if newIndex < videos.count {
                        withAnimation {
                            proxy.scrollTo(videos[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            ControlDotView(
                isExpanded: $isDotExpanded,
                userName: Auth.auth().currentUser?.displayName ?? "User",
                dotColor: likesService.isLiked(videoId: currentVideo?.id ?? "") ? .red : .white,
                likesService: likesService,
                bookmarksService: bookmarksService,
                currentVideoId: currentVideo?.id ?? "",
                onBookmarkAction: {
                    if let video = currentVideo {
                        handleUnbookmark(video)
                    }
                },
                onProfileAction: { dismiss() }
            )
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(2)
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.width > 100 {
                        dismiss()
                    }
                }
        )
    }

private func handleUnbookmark(_ video: VideoPlayerData) {
    // Simply toggle the bookmark in Firestore; the onChange handler will update the local state.
    bookmarksService.toggleBookmark(videoId: video.id)
}
} 
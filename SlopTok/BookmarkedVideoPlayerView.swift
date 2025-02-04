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
        // Determine the next index to scroll to
        let nextIndex: Int?
        if video.index == videos.count - 1 {
            // If removing the last video, scroll up
            nextIndex = video.previous
        } else {
            // Otherwise, show next video at the same index
            nextIndex = video.index
        }

        withAnimation {
            // Remove the video from the local state
            videos.removeAll { $0.id == video.id }

            // Reindex remaining videos
            for i in 0..<videos.count {
                videos[i] = VideoPlayerData(
                    id: videos[i].id,
                    timestamp: videos[i].timestamp,
                    index: i
                )
            }

            // Update scroll position if available
            if let next = nextIndex, next < videos.count {
                currentIndex = next
            } else if let next = nextIndex, next >= videos.count, next > 0 {
                currentIndex = next - 1
            }
        }

        // Then update Firestore
        bookmarksService.toggleBookmark(videoId: video.id)
    }
} 
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
    
    var currentVideo: VideoPlayerModel? {
        guard currentIndex >= 0 && currentIndex < videos.count else { return nil }
        return videos[currentIndex]
    }
    
    init(bookmarkedVideos: [BookmarkedVideo], initialIndex: Int, bookmarksService: BookmarksService) {
        print(" [BookmarkedVideoPlayerView] Initializing with \(bookmarkedVideos.count) videos, initial index: \(initialIndex)")
        self.bookmarksService = bookmarksService
        self.initialIndex = initialIndex
        
        // Create initial video data with indices
        let videoData = bookmarkedVideos.enumerated().map { index, video in
            VideoPlayerModel(id: video.id, timestamp: video.timestamp, index: index)
        }
        print(" [BookmarkedVideoPlayerView] Created initial video data with \(videoData.count) videos")
        
        // Initialize state
        _videos = State(initialValue: videoData)
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        SavedVideoPlayerView<BookmarkedVideo, BookmarksService, BookmarkedVideoPlayerCell>(
            savedVideos: bookmarksService.bookmarkedVideos,
            initialIndex: initialIndex,
            savedVideoService: bookmarksService,
            likesService: likesService,
            bookmarksService: bookmarksService,
            dotColor: likesService.isLiked(videoId: currentVideo?.id ?? "") ? .red : .white,
            onBookmarkAction: {
                if let video = currentVideo {
                    bookmarksService.toggleBookmark(videoId: video.id)
                }
            }
        )
        .task {
            await likesService.loadLikedVideos()
        }
        .onChange(of: bookmarksService.bookmarkedVideos) { newBookmarks in
            print(" [BookmarkedVideoPlayerView] Bookmarks changed - New count: \(newBookmarks.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let newData = newBookmarks.enumerated().map { index, bookmark in
                    VideoPlayerModel(id: bookmark.id, timestamp: bookmark.timestamp, index: index)
                }
                print(" [BookmarkedVideoPlayerView] Created new video data with \(newData.count) videos (after delay)")
                withAnimation(.easeInOut) {
                    let oldCount = videos.count
                    let oldIndex = currentIndex
                    videos = newData
                    print(" [BookmarkedVideoPlayerView] State update - Old count: \(oldCount), New count: \(videos.count), Old index: \(oldIndex), Current index: \(currentIndex)")
                    
                    if videos.isEmpty {
                        print(" [BookmarkedVideoPlayerView] No videos left, dismissing")
                        currentIndex = 0
                        dismiss()
                    } else if currentIndex >= videos.count {
                        print(" [BookmarkedVideoPlayerView] Current index out of bounds, adjusting to \(max(0, videos.count - 1))")
                        currentIndex = max(0, videos.count - 1)
                    }
                }
            }
        }
    }
}
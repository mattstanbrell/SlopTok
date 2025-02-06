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
    
    var body: some View {
        SavedVideoPlayerView<LikedVideo, LikesService, LikedVideoPlayerCell>(
            savedVideos: likesService.likedVideos,
            initialIndex: initialIndex,
            savedVideoService: likesService,
            likesService: likesService,
            bookmarksService: bookmarksService,
            dotColor: .red,
            onBookmarkAction: nil
        )
        .task {
            await bookmarksService.loadBookmarkedVideos()
        }
        .onChange(of: likesService.likedVideos) { newLikes in
            print(" [LikedVideoPlayerView] Likes changed - New count: \(newLikes.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let newData = newLikes.enumerated().map { index, like in
                    VideoPlayerModel(id: like.id, timestamp: like.timestamp, index: index)
                }
                print(" [LikedVideoPlayerView] Created new video data with \(newData.count) videos (after delay)")
                withAnimation(.easeInOut) {
                    let oldCount = videos.count
                    let oldIndex = currentIndex
                    videos = newData
                    print(" [LikedVideoPlayerView] State update - Old count: \(oldCount), New count: \(videos.count), Old index: \(oldIndex), Current index: \(currentIndex)")
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
    }
    
    var currentVideo: VideoPlayerModel? {
        guard currentIndex >= 0 && currentIndex < videos.count else { return nil }
        return videos[currentIndex]
    }
}
import FirebaseFirestore
import FirebaseAuth

@MainActor
class BookmarksService: SavedVideoService<BookmarkedVideo> {
    init() {
        super.init(
            collectionName: "bookmarks",
            createVideo: { BookmarkedVideo(id: $0, timestamp: $1) }
        )
    }
    
    var bookmarkedVideos: [BookmarkedVideo] { videos }
    var bookmarkedVideosPublisher: Published<[BookmarkedVideo]>.Publisher { $videos }
    
    func loadBookmarkedVideos() async {
        await loadVideos()
    }
    
    func toggleBookmark(videoId: String) {
        toggleSavedState(videoId: videoId)
    }
    
    func isBookmarked(videoId: String) -> Bool {
        isSaved(videoId: videoId)
    }
}

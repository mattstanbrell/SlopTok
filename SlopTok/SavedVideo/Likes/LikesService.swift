import FirebaseFirestore
import FirebaseAuth

@MainActor
class LikesService: SavedVideoService<LikedVideo> {
    init() {
        super.init(
            collectionName: "likes",
            createVideo: { LikedVideo(id: $0, timestamp: $1) }
        )
    }
    
    var likedVideos: [LikedVideo] { videos }
    var likedVideosPublisher: Published<[LikedVideo]>.Publisher { $videos }
    
    func loadLikedVideos() async {
        await loadVideos()
    }
    
    func toggleLike(videoId: String) {
        toggleSavedState(videoId: videoId)
    }
    
    func isLiked(videoId: String) -> Bool {
        isSaved(videoId: videoId)
    }
}
